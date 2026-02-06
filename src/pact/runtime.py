class PactSome:
    def __init__(self, value):
        self.value = value

    def __str__(self):
        return str(self.value)


class _PactNone:
    def __str__(self):
        return "None"


NONE = _PactNone()


class PactList:
    def __init__(self, items):
        self._items = list(items)

    def get(self, index):
        if 0 <= index < len(self._items):
            return PactSome(self._items[index])
        return NONE

    def len(self):
        return len(self._items)


class IOHandle:
    def println(self, value):
        print(value)


class EnvHandle:
    def __init__(self, argv):
        self._argv = argv

    def args(self):
        return PactList(self._argv)
