import pact.runtime as runtime


class TestPactSome:
    def test_str(self):
        assert str(runtime.PactSome(42)) == "42"


class TestPactNone:
    def test_str(self):
        assert str(runtime.NONE) == "None"


class TestPactList:
    def test_get_in_bounds(self):
        lst = runtime.PactList(["a", "b", "c"])
        result = lst.get(1)
        assert isinstance(result, runtime.PactSome)
        assert result.value == "b"

    def test_get_out_of_bounds(self):
        lst = runtime.PactList(["a", "b"])
        assert lst.get(5) is runtime.NONE

    def test_len(self):
        lst = runtime.PactList([1, 2, 3])
        assert lst.len() == 3

    def test_empty(self):
        lst = runtime.PactList([])
        assert lst.len() == 0
        assert lst.get(0) is runtime.NONE


class TestIOHandle:
    def test_println(self, capsys):
        io = runtime.IOHandle()
        io.println("hello pact")
        assert capsys.readouterr().out == "hello pact\n"


class TestEnvHandle:
    def test_args(self):
        env = runtime.EnvHandle(["pact", "run", "main.pact"])
        args = env.args()
        assert isinstance(args, runtime.PactList)
        assert args.len() == 3
        assert args.get(0).value == "pact"
