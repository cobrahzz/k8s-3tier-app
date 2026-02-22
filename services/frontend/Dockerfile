FROM nginx:1.27-alpine
COPY 11-set-resolver.envsh /docker-entrypoint.d/11-set-resolver.envsh
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY src/ /usr/share/nginx/html/
EXPOSE 80
