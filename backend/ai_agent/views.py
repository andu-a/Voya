from __future__ import annotations

import json
import logging

from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from .models import ConversationLog
from .serializers import (
    ChatRequestSerializer,
    ConversationLogSerializer,
)
from .agents.supervisor_agent import SupervisorAgent


logger = logging.getLogger(__name__)


def build_conversation_history(user):
    recent_logs = ConversationLog.objects.filter(
        user=user,
        status='success',
    ).order_by('-created_at')[:10]

    conversation_history = []
    for log in reversed(list(recent_logs)):
        if log.user_prompt:
            conversation_history.append({"role": "user", "content": log.user_prompt})
        if log.response:
            conversation_history.append({"role": "assistant", "content": log.response})
    return conversation_history


@api_view(['POST'])
def chat(request):
    req_serializer = ChatRequestSerializer(data=request.data)
    if not req_serializer.is_valid():
        return Response(req_serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    user_prompt = req_serializer.validated_data['prompt']
    conversation_history = build_conversation_history(request.user)

    try:
        supervisor = SupervisorAgent()
        result = supervisor.run(user_prompt, conversation_history=conversation_history)
    except Exception:
        logger.exception('ai_agent chat processing failed')
        return Response(
            {
                'success': False,
                'error': 'A aparut o eroare interna la procesarea cererii.',
                'final_response': None,
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    vr = result.get('validation_result') or {}
    is_valid = vr.get('is_valid', False)

    ConversationLog.objects.create(
        user=request.user,
        user_prompt=user_prompt,
        formatted_prompt=json.dumps(vr, ensure_ascii=False) if is_valid else None,
        assigned_agent=', '.join(result.get('assigned_agents', [])) or None,
        response=result.get('final_response'),
        status='success' if is_valid else 'rejected',
        rejection_reason=result.get('error') if not is_valid else None,
    )

    response_data = {
        'success': is_valid,
        'final_response': result.get('final_response'),
        'assigned_agents': result.get('assigned_agents', []),
        'validation': {
            'intent': vr.get('intent'),
            'destinations': vr.get('destinations', []),
            'origin': vr.get('origin'),
            'travel_dates': vr.get('travel_dates'),
            'travelers_count': vr.get('travelers_count'),
            'budget': vr.get('budget'),
        },
        'agent_responses': result.get('agent_responses', {}),
        'sources': result.get('sources', []),
        'tool_metadata': result.get('tool_metadata', {}),
        'error': result.get('error'),
    }

    http_status = status.HTTP_200_OK if is_valid else status.HTTP_422_UNPROCESSABLE_ENTITY
    return Response(response_data, status=http_status)


@api_view(['GET'])
def conversation_history(request):
    logs = ConversationLog.objects.filter(user=request.user).order_by('-created_at')
    serializer = ConversationLogSerializer(logs, many=True)
    return Response(serializer.data, status=status.HTTP_200_OK)


@api_view(['GET'])
def conversation_detail(request, pk):
    try:
        log = ConversationLog.objects.get(pk=pk, user=request.user)
    except ConversationLog.DoesNotExist:
        return Response({'error': 'Conversation not found'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ConversationLogSerializer(log)
    return Response(serializer.data, status=status.HTTP_200_OK)


@api_view(['GET'])
def agent_info(request):
    agents_info = [
        {
            'name': 'validation_agent',
            'role': 'Validator & Formatter',
            'description': 'Verifica daca promptul este despre calatorii si il formateaza.',
            'is_supervisor': False,
            'is_internal': True,
        },
        {
            'name': 'supervisor_agent',
            'role': 'Supervisor',
            'description': 'Decide ce sub-agenti sa activeze in functie de tipul cererii.',
            'is_supervisor': True,
            'is_internal': False,
        },
        {
            'name': 'flight_agent',
            'role': 'Sub-agent',
            'description': 'Expert in zboruri, rute aeriene, companii aeriene si bilete.',
            'is_supervisor': False,
            'is_internal': False,
        },
        {
            'name': 'hotel_agent',
            'role': 'Sub-agent',
            'description': 'Expert in cazare, hoteluri si rezervari.',
            'is_supervisor': False,
            'is_internal': False,
        },
        {
            'name': 'general_travel_agent',
            'role': 'Sub-agent',
            'description': 'Expert in destinatii, itinerare, cultura locala si vize.',
            'is_supervisor': False,
            'is_internal': False,
        },
        {
            'name': 'budget_planning_agent',
            'role': 'Sub-agent',
            'description': 'Expert in planificarea bugetului si costurile de calatorie.',
            'is_supervisor': False,
            'is_internal': False,
        },
    ]
    return Response({'agents': agents_info}, status=status.HTTP_200_OK)
