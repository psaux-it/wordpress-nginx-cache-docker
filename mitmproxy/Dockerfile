# Dockerfile for NPP mitmproxy service                                             #
# ----------------------------------------------------------------------------     #
# Author: [Hasan ÇALIŞIR]                                                          #
# Purpose: Local HTTP proxy for NPP cache preload requests.                        #
#          Rewrites localhost → nginx container for correct routing inside Docker. #
# ----------------------------------------------------------------------------     #

FROM mitmproxy/mitmproxy:latest

# Copy NPP addon script
COPY mitmproxy/npp_addon.py /home/mitmproxy/npp_addon.py
RUN chown mitmproxy:mitmproxy /home/mitmproxy/npp_addon.py

CMD ["mitmdump", \
     "--mode", "regular", \
     "--listen-host", "0.0.0.0", \
     "--listen-port", "3434", \
     "--set", "ssl_insecure=true", \
     "--set", "block_global=false", \
     "--set", "upstream_cert=false", \
     "--no-http2", \
     "-s", "/home/mitmproxy/npp_addon.py"]
