from django.db import models
from django.conf import settings


class ConversationLog(models.Model):
    """Logs every interaction with the AI agent system."""

    STATUS_CHOICES = [
        ('success', 'Success'),
        ('rejected', 'Rejected - Not Travel Related'),
        ('error', 'Error'),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='conversation_logs',
    )
    user_prompt = models.TextField()
    formatted_prompt = models.TextField(blank=True, null=True)
    assigned_agent = models.CharField(max_length=100, blank=True, null=True)
    response = models.TextField(blank=True, null=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='success')
    rejection_reason = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Conversation Log'
        verbose_name_plural = 'Conversation Logs'

    def __str__(self):
        return f"[{self.status}] {self.user_prompt[:60]}... @ {self.created_at}"
