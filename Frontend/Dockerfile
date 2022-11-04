# STAGE 1
FROM node:16-alpine AS build
RUN apk update && apk add --update alpine-sdk
# Install python/pip
ENV PYTHONUNBUFFERED=1
RUN apk add --update --no-cache python3 && ln -sf python3 /usr/bin/python
RUN python3 -m ensurepip
RUN pip3 install --no-cache --upgrade pip setuptools

ARG api_endpoint
ENV REACT_APP_TODO_APP_API_ENDPOINT $api_endpoint

WORKDIR /app
COPY package.json ./

RUN yarn install
COPY . /app
RUN yarn build

# STAGE 2
FROM nginx:stable-alpine
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
