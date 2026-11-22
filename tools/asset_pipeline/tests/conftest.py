import pytest


@pytest.fixture
def root(tmp_path, monkeypatch):
    (tmp_path / "project.godot").write_text("")
    monkeypatch.setenv("ASSET_PIPELINE_ROOT", str(tmp_path))
    return tmp_path


@pytest.fixture(autouse=True)
def no_live_network(monkeypatch):
    """No test may reach a real host: only loopback connections are allowed."""
    import socket
    real = socket.socket.connect

    def guarded(self, address, *a, **k):
        host = address[0] if isinstance(address, tuple) else address
        if isinstance(host, str) and host not in ("127.0.0.1", "::1", "localhost") and self.family != socket.AF_UNIX:
            raise AssertionError(f"test tried a live network connection to {host}")
        return real(self, address, *a, **k)

    monkeypatch.setattr(socket.socket, "connect", guarded)
