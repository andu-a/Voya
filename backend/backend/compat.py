import sys
from copy import copy

import django


def apply_python314_django_context_copy_patch():
    if sys.version_info < (3, 14) or django.VERSION >= (5, 0):
        return

    from django.template import context as django_context

    if getattr(django_context.BaseContext.__copy__, "__module__", "") == __name__:
        return

    def base_context_copy(self):
        duplicate = object.__new__(self.__class__)
        duplicate.__dict__ = self.__dict__.copy()
        duplicate.dicts = self.dicts[:]
        return duplicate

    def context_copy(self):
        duplicate = base_context_copy(self)
        duplicate.render_context = copy(self.render_context)
        return duplicate

    django_context.BaseContext.__copy__ = base_context_copy
    django_context.Context.__copy__ = context_copy


apply_python314_django_context_copy_patch()
