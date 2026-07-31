from django.contrib import admin
from .models import ConversationLog


@admin.register(ConversationLog)
class ConversationLogAdmin(admin.ModelAdmin):
    list_display = ['id', 'user', 'short_prompt', 'assigned_agent', 'status', 'created_at']
    list_filter = ['status', 'assigned_agent', 'created_at', 'user']
    search_fields = ['user__username', 'user__email', 'user_prompt', 'response']
    readonly_fields = [
        'user', 'user_prompt', 'formatted_prompt', 'assigned_agent',
        'response', 'status', 'rejection_reason', 'created_at',
    ]
    ordering = ['-created_at']
    list_select_related = ['user']
    date_hierarchy = 'created_at'

    fieldsets = (
        ('Conversation', {
            'fields': ('user', 'status', 'assigned_agent', 'created_at'),
        }),
        ('Request', {
            'fields': ('user_prompt', 'formatted_prompt'),
        }),
        ('Response', {
            'fields': ('response', 'rejection_reason'),
        }),
    )

    def short_prompt(self, obj):
        return obj.user_prompt[:80] + '...' if len(obj.user_prompt) > 80 else obj.user_prompt
    short_prompt.short_description = 'Prompt'
