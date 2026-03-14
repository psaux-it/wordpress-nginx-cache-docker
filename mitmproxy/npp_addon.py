from mitmproxy import http


class NPPAddon:
    def http_connect(self, flow: http.HTTPFlow) -> None:
        # Rewrite localhost → nginx (Docker service name) for CONNECT tunneling
        if flow.request.host == 'localhost':
            flow.request.host = 'nginx'


addons = [NPPAddon()]
