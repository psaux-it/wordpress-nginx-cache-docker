from mitmproxy import http

class NPPAddon:
    def http_connect(self, flow):
        # Rewrite localhost → nginx (Docker service name) for CONNECT tunneling
        if flow.server_conn.address[0] == 'localhost':
            flow.server_conn.address = ('nginx', flow.server_conn.address[1])

    def request(self, flow: http.HTTPFlow) -> None:
        # Rewrite localhost → nginx for direct requests
        if flow.request.pretty_host == 'localhost':
            flow.request.host = 'nginx'

addons = [NPPAddon()]
