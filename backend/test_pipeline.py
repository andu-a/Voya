import sys, os
sys.path.insert(0, '.')
os.environ['DJANGO_SETTINGS_MODULE'] = 'backend.settings'
import django; django.setup()
import logging; logging.disable(logging.CRITICAL)

from ai_agent.agents.supervisor_agent import SupervisorAgent
result = SupervisorAgent().run('Ce pot vizita la Paris?')
print('INTENT:', result['validation_result'].get('intent'))
print('AGENTS:', result['assigned_agents'])
print('ERROR:', result['error'])
print('RESPONSE:', result['final_response'][:200] if result['final_response'] else None)
