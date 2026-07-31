from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name='ConversationLog',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('user_prompt', models.TextField()),
                ('formatted_prompt', models.TextField(blank=True, null=True)),
                ('assigned_agent', models.CharField(blank=True, max_length=100, null=True)),
                ('response', models.TextField(blank=True, null=True)),
                ('status', models.CharField(
                    choices=[('success', 'Success'), ('rejected', 'Rejected - Not Travel Related'), ('error', 'Error')],
                    default='success',
                    max_length=20,
                )),
                ('rejection_reason', models.TextField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={
                'verbose_name': 'Conversation Log',
                'verbose_name_plural': 'Conversation Logs',
                'ordering': ['-created_at'],
            },
        ),
    ]
