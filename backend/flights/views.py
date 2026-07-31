from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from amadeus import Client, ResponseError, Location
from dotenv import load_dotenv
import os
from pathlib import Path
from datetime import datetime
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from .models import FlightBooking

load_dotenv(Path(__file__).resolve().parent.parent / '.env')


def build_amadeus_error_response(error):
	details = None
	status_code = 400
	message = str(error)
	try:
		details = error.response.result
	except Exception:
		pass
	try:
		status_code = error.response.status_code
	except Exception:
		try:
			status_code = int(details.get('errors', [{}])[0].get('status', 400))
		except Exception:
			status_code = 400
	if isinstance(details, dict):
		api_errors = details.get('errors')
		if isinstance(api_errors, list) and api_errors:
			first_error = api_errors[0] if isinstance(api_errors[0], dict) else {}
			message = first_error.get('detail') or first_error.get('title') or message
	if status_code >= 500:
		message = 'Amadeus service is temporarily unavailable. Please try again later.'
		status_code = 503
	return Response({'error': message, 'details': details}, status=status_code)


def get_amadeus_client():
	client_id = (os.environ.get('AMADEUS_CLIENT_ID') or '').strip()
	client_secret = (os.environ.get('AMADEUS_CLIENT_SECRET') or '').strip()
	hostname = (os.environ.get('AMADEUS_HOSTNAME') or 'test').strip()

	if not client_id or not client_secret:
		raise ValueError(
			'Missing Amadeus credentials. Set AMADEUS_CLIENT_ID and AMADEUS_CLIENT_SECRET on server environment.'
		)

	client_kwargs = {
		'client_id': client_id,
		'client_secret': client_secret,
	}
	if hostname:
		client_kwargs['hostname'] = hostname

	return Client(**client_kwargs)


def ensure_pricing_fields(offer, segments):
	if not offer.get('type'):
		offer['type'] = 'flight-offer'
	if not offer.get('id'):
		carrier_code = segments[0].get('carrierCode') if segments else 'XX'
		dep = segments[0]['departure']['at'][:10] if segments else '0000-00-00'
		offer['id'] = f"{carrier_code}-{dep}"
	if not offer.get('validatingAirlineCodes'):
		carrier_code = segments[0].get('carrierCode') if segments else None
		if carrier_code:
			offer['validatingAirlineCodes'] = [carrier_code]
	return offer


def format_datetime(raw):
	if not raw:
		return ''
	try:
		dt = datetime.fromisoformat(raw)
		return dt.strftime('%Y-%m-%d %H:%M')
	except Exception:
		return raw


def ensure_aware_datetime(raw):
	if isinstance(raw, datetime):
		dt = raw
	elif isinstance(raw, str) and raw.strip():
		dt = parse_datetime(raw.strip())
		if dt is None:
			raise ValueError(f'Invalid datetime value: {raw}')
	else:
		return timezone.now()

	if timezone.is_naive(dt):
		dt = timezone.make_aware(dt, timezone.get_current_timezone())
	return dt


def parse_search_query_params(request):
	origin = (request.GET.get('origin') or '').strip().upper()
	destination = (request.GET.get('destination') or '').strip().upper()
	departure_date = (request.GET.get('departureDate') or '').strip()
	trip_type = (request.GET.get('trip_type', 'oneway') or 'oneway').strip().lower()
	arrival_date = (request.GET.get('arrivalDate') or '').strip()
	adults = (request.GET.get('adults', '1') or '1').strip()

	if trip_type == 'roundtrip':
		trip_type = 'round'

	missing = []
	if not origin:
		missing.append('origin')
	if not destination:
		missing.append('destination')
	if not departure_date:
		missing.append('departureDate')
	if trip_type == 'round' and not arrival_date:
		missing.append('arrivalDate')
	if missing:
		return None, Response(
			{'error': 'Missing required query parameters', 'missing': missing},
			status=400
		)

	if trip_type not in {'oneway', 'round'}:
		return None, Response(
			{'error': 'Invalid trip_type', 'allowed': ['oneway', 'round']},
			status=400
		)

	if len(origin) != 3 or not origin.isalpha():
		return None, Response({'error': 'Invalid origin (expected 3-letter IATA code)'}, status=400)
	if len(destination) != 3 or not destination.isalpha():
		return None, Response({'error': 'Invalid destination (expected 3-letter IATA code)'}, status=400)

	try:
		adults_int = int(adults)
		if adults_int < 1:
			raise ValueError('adults must be >= 1')
	except (TypeError, ValueError):
		return None, Response({'error': 'Invalid adults (must be an integer >= 1)'}, status=400)

	from datetime import date
	try:
		date.fromisoformat(departure_date)
		if arrival_date:
			date.fromisoformat(arrival_date)
	except ValueError:
		return None, Response({'error': 'Invalid date format (expected YYYY-MM-DD)'}, status=400)

	return {
		'origin': origin,
		'destination': destination,
		'departure_date': departure_date,
		'trip_type': trip_type,
		'arrival_date': arrival_date,
		'adults_int': adults_int,
	}, None


def build_display_from_offer(offer):
	itineraries = offer.get('itineraries') or []
	if not itineraries:
		return {}

	first_itinerary = itineraries[0] if isinstance(itineraries[0], dict) else {}
	first_segments = first_itinerary.get('segments') or []
	if not first_segments:
		return {}

	first_segment = first_segments[0] if isinstance(first_segments[0], dict) else {}
	last_segment = first_segments[-1] if isinstance(first_segments[-1], dict) else {}
	display = {
		'origin': first_segment.get('departure', {}).get('iataCode', ''),
		'destination': last_segment.get('arrival', {}).get('iataCode', ''),
		'departure': format_datetime(first_segment.get('departure', {}).get('at', '')),
		'arrival': format_datetime(last_segment.get('arrival', {}).get('at', '')),
		'stops': max(len(first_segments) - 1, 0),
	}

	if len(itineraries) > 1 and isinstance(itineraries[1], dict):
		return_segments = itineraries[1].get('segments') or []
		if return_segments:
			return_first = return_segments[0] if isinstance(return_segments[0], dict) else {}
			return_last = return_segments[-1] if isinstance(return_segments[-1], dict) else {}
			display['return_departure'] = format_datetime(return_first.get('departure', {}).get('at', ''))
			display['return_arrival'] = format_datetime(return_last.get('arrival', {}).get('at', ''))
			display['return_stops'] = max(len(return_segments) - 1, 0)

	return display


def normalize_amadeus_offer(offer, dictionaries=None):
	dictionaries = dictionaries or {}
	carrier_lookup = dictionaries.get('carriers') or {}
	itineraries = offer.get('itineraries') or []
	segments = []
	if itineraries and isinstance(itineraries[0], dict):
		segments = itineraries[0].get('segments') or []

	offer = ensure_pricing_fields(offer, segments)
	validating_codes = offer.get('validatingAirlineCodes') or []
	primary_code = validating_codes[0] if validating_codes else (segments[0].get('carrierCode') if segments else '')
	offer['airline_name'] = carrier_lookup.get(primary_code, primary_code or 'Unknown airline')
	offer['display'] = build_display_from_offer(offer)
	return offer


@api_view(['GET'])
def select_destination(request, param):
	try:
		amadeus = get_amadeus_client()
		response = amadeus.reference_data.locations.get(
			keyword=param,
			subType=Location.ANY,
		)
		normalized = [
			{
				'iataCode': loc.get('iataCode', ''),
				'name': loc.get('name', ''),
				'cityName': loc.get('address', {}).get('cityName', ''),
				'countryName': loc.get('address', {}).get('countryName', ''),
				'subType': loc.get('subType', ''),
			}
			for loc in response.data
			if loc.get('iataCode')
		]
		return Response({'data': normalized}, status=200)
	except ResponseError as error:
		return build_amadeus_error_response(error)
	except Exception as e:
		return Response({'error': str(e)}, status=500)


def search_flight_with_amadeus(request):
	params, error_response = parse_search_query_params(request)
	if error_response:
		return error_response

	try:
		amadeus = get_amadeus_client()
		query = {
			'originLocationCode': params['origin'],
			'destinationLocationCode': params['destination'],
			'departureDate': params['departure_date'],
			'adults': params['adults_int'],
			'max': 10,
		}
		if params['trip_type'] == 'round' and params['arrival_date']:
			query['returnDate'] = params['arrival_date']

		response = amadeus.shopping.flight_offers_search.get(**query)
		result = response.result if isinstance(response.result, dict) else {}
		dictionaries = result.get('dictionaries') if isinstance(result, dict) else {}
		raw_offers = result.get('data') if isinstance(result, dict) else None
		if raw_offers is None:
			raw_offers = getattr(response, 'data', []) or []

		offers = [
			normalize_amadeus_offer(dict(offer), dictionaries)
			for offer in raw_offers
			if isinstance(offer, dict)
		]

		return Response({
			'offers': offers,
			'meta': result.get('meta', {}),
		}, status=200)
	except ValueError as error:
		return Response({'error': str(error)}, status=500)
	except ResponseError as error:
		return build_amadeus_error_response(error)


@api_view(['GET'])
def search_flight(request):
	return search_flight_with_amadeus(request)


@api_view(['GET'])
def search_flight_amadeus(request):
	return search_flight_with_amadeus(request)


@api_view(['POST'])
def price_offer(request):
	try:
		amadeus = get_amadeus_client()
		payload = request.data
		data = payload.get('data') if isinstance(payload, dict) else None
		flight_offers = (data.get('flightOffers') or []) if isinstance(data, dict) else []
		if not flight_offers:
			return Response({'error': 'No flight offers provided'}, status=400)

		extra_fields = {'airline_name', 'checkin_link', 'display'}
		cleaned_offers = []
		for offer in flight_offers:
			if not isinstance(offer, dict):
				continue
			offer = {k: v for k, v in offer.items() if k not in extra_fields}
			segments = offer.get('itineraries', [{}])[0].get('segments', [])
			cleaned_offers.append(ensure_pricing_fields(offer, segments))

		if not cleaned_offers:
			return Response({'error': 'No valid flight offers'}, status=400)

		response = amadeus.shopping.flight_offers.pricing.post(cleaned_offers)
		priced_offers = response.data.get('flightOffers', []) if isinstance(response.data, dict) else []
		priced_offer = priced_offers[0] if priced_offers else {}
		price_data = priced_offer.get('price', {}) if isinstance(priced_offer, dict) else {}
		return Response({
			'offer': priced_offer,
			'display': {
				'price_total': price_data.get('total'),
				'price_currency': price_data.get('currency', 'EUR'),
			}
		}, status=200)
	except ResponseError as error:
		return build_amadeus_error_response(error)
	except Exception as e:
		return Response({'error': str(e)}, status=500)


@api_view(['POST'])
def book_flight(request):
	try:
		amadeus = get_amadeus_client()
		payload = request.data
		data = payload.get('data', {}) if isinstance(payload, dict) else {}
		flight_offers = data.get('flightOffers', [])
		travelers_list = data.get('travelers', [])

		if not flight_offers:
			return Response({'error': 'No flight offers provided'}, status=400)
		if not travelers_list:
			return Response({'error': 'No travelers provided'}, status=400)

		response = amadeus.booking.flight_orders.post(flight_offers, travelers_list)
		amadeus_data = response.data

		associated = amadeus_data.get('associatedRecords', [])
		pnr = associated[0].get('reference', '') if associated else ''
		order_id = amadeus_data.get('id', '')

		flight_offers = amadeus_data.get('flightOffers', [])
		offer = flight_offers[0] if flight_offers else {}
		itineraries = offer.get('itineraries', [])
		segments = itineraries[0].get('segments', []) if itineraries else []
		first_seg = segments[0] if segments else {}
		last_seg = segments[-1] if segments else first_seg

		dep_raw = first_seg.get('departure', {}).get('at', '')
		arr_raw = last_seg.get('arrival', {}).get('at', '')
		price_info = offer.get('price', {})
		trip_type = 'round' if len(itineraries) > 1 else 'oneway'
		carrier_code = first_seg.get('carrierCode', '')

		airline_name = carrier_code
		try:
			airline_resp = amadeus.reference_data.airlines.get(airlineCodes=carrier_code)
			if airline_resp.data:
				airline_name = airline_resp.data[0].get('businessName') or carrier_code
		except Exception:
			pass

		checkin_link = ''
		if carrier_code:
			try:
				checkin_resp = amadeus.reference_data.urls.checkin_links.get(airlineCode=carrier_code)
				if checkin_resp.data:
					checkin_link = checkin_resp.data[0].get('href') or checkin_resp.data[0].get('url') or ''
			except Exception:
				pass

		booking = FlightBooking.objects.create(
			user=request.user,
			amadeus_order_id=order_id,
			pnr=pnr,
			airline_name=airline_name,
			origin=first_seg.get('departure', {}).get('iataCode', ''),
			destination=last_seg.get('arrival', {}).get('iataCode', ''),
			departure_at=ensure_aware_datetime(dep_raw),
			arrival_at=ensure_aware_datetime(arr_raw),
			stops=max(len(segments) - 1, 0),
			price_total=price_info.get('total', '0'),
			price_currency=price_info.get('currency', 'EUR'),
			trip_type=trip_type,
			checkin_link=checkin_link,
			amadeus_response=amadeus_data,
		)

		return Response({
			'id': booking.id,
			'pnr': pnr,
			'amadeus_order_id': order_id,
			'status': booking.status,
			'message': 'Flight booked successfully',
		}, status=201)
	except ResponseError as error:
		return build_amadeus_error_response(error)
	except Exception as e:
		return Response({'error': str(e)}, status=500)


@api_view(['GET'])
def get_bookings(request):
	bookings = FlightBooking.objects.filter(user=request.user)
	data = []
	for b in bookings:
		data.append({
			'id': b.id,
			'pnr': b.pnr,
			'amadeus_order_id': b.amadeus_order_id,
			'airline_name': b.airline_name,
			'origin': b.origin,
			'destination': b.destination,
			'departure_at': b.departure_at.strftime('%Y-%m-%d %H:%M'),
			'arrival_at': b.arrival_at.strftime('%Y-%m-%d %H:%M'),
			'stops': b.stops,
			'price_total': str(b.price_total),
			'price_currency': b.price_currency,
			'trip_type': b.trip_type,
			'checkin_link': b.checkin_link,
			'status': b.status,
			'created_at': b.created_at.strftime('%Y-%m-%d %H:%M'),
		})
	return Response(data, status=200)


@api_view(['PATCH'])
def cancel_booking(request, pk):
	try:
		booking = FlightBooking.objects.get(pk=pk, user=request.user)
	except FlightBooking.DoesNotExist:
		return Response({'error': 'Booking not found'}, status=404)

	if booking.status == 'CANCELLED':
		return Response({'error': 'Booking is already cancelled'}, status=400)

	booking.status = 'CANCELLED'
	booking.save()
	return Response({'message': 'Booking cancelled', 'status': booking.status}, status=200)
