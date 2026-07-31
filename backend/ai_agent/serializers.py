from rest_framework import serializers
from .models import ConversationLog


class ChatRequestSerializer(serializers.Serializer):
    prompt = serializers.CharField(
        max_length=2000,
        help_text="Intrebarea sau cererea utilizatorului despre calatorii.",
    )


class ConversationLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = ConversationLog
        fields = [
            'id', 'user_prompt', 'formatted_prompt',
            'assigned_agent', 'response', 'status',
            'rejection_reason', 'created_at',
        ]
        read_only_fields = fields
