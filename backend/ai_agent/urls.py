from django.urls import path
from .views import chat, conversation_history, conversation_detail, agent_info

urlpatterns = [
    path('chat/', chat, name='ai-chat'),
    path('agents/', agent_info, name='ai-agents-info'),
    path('history/', conversation_history, name='ai-history'),
    path('history/<int:pk>/', conversation_detail, name='ai-history-detail'),
]
