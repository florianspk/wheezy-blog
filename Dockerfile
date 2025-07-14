FROM hugomods/hugo:debian-node-git-0.148.1 AS builder
WORKDIR /src
COPY . .
RUN hugo --minify

FROM nginx:1.13.0-alpine as nginx
LABEL maintainer="florian@florianspk.fr"

COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
