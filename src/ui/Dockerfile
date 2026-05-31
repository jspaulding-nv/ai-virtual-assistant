FROM nvcr.io/nvidia/blueprint/aiva-customer-service-ui:1.1.0

COPY src/ui/product_icon_fallback.js /tmp/product_icon_fallback.js

RUN set -eux; \
    patched=0; \
    for file in $(find / -type f -name "*.js" \( -path "*/_next/static/chunks/app/*" -o -path "*/_next/static/chunks/pages/*" -o -path "*/_next/static/chunks/main-*.js" \) 2>/dev/null); do \
        cat /tmp/product_icon_fallback.js >> "$file"; \
        patched=$((patched + 1)); \
    done; \
    if [ "$patched" -eq 0 ]; then \
        for file in $(find / -type f -name "page-*.js" 2>/dev/null); do \
            cat /tmp/product_icon_fallback.js >> "$file"; \
            patched=$((patched + 1)); \
        done; \
    fi; \
    find / -type f \( -name "*.js.gz" -o -name "*.js.br" \) -path "*/_next/static/*" -delete 2>/dev/null || true; \
    test "$patched" -gt 0
