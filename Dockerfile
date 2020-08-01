FROM geoffreybooth/meteor-base:1.10.2 as base

LABEL maintainer="lior@haim.com" 

RUN mkdir -p /tmp/builder

WORKDIR /tmp/builder

# Copy all dependencies 
RUN mkdir .scripts
COPY package.json .
COPY ./scripts .scripts/

# Install meteor build dependencies
RUN mkdir -p app/katex
RUN meteor npm ci --silent

# Copy app source into container
COPY . /tmp/builder/

# Build meteor bundle
RUN mkdir -p /tmp/appbundle \
    && meteor build --directory /tmp/appbundle --server-only

# Use the specific version of Node expected by your Meteor release, per https://docs.meteor.com/changelog.html; this is expected for Meteor 1.10.2
FROM node:12.16.1-buster-slim as preps

# Copy in app bundle
COPY --from=base /tmp/appbundle /app

RUN groupadd -g 65533 -r rocketchat \
    && useradd -u 65533 -r -g rocketchat rocketchat \
    && mkdir -p /app/uploads \
    && chown rocketchat:rocketchat /app/uploads \
    && apt-get update \
    && apt-get install -y --no-install-recommends fontconfig

# Start app
RUN apt-get install -y --no-install-recommends g++ make python ca-certificates

WORKDIR /app/bundle/programs/server

# Install app runtime dependencies
RUN npm install --silent

RUN aptMark="$(apt-mark showmanual)" \
    && apt-mark auto '.*' > /dev/null \
    && apt-mark manual $aptMark > /dev/null \
    && find /usr/local -type f -executable -exec ldd '{}' ';' \
       | awk '/=>/ { print $(NF-1) }' \
       | sort -u \
       | xargs -r dpkg-query --search \
       | cut -d: -f1 \
       | sort -u \
       | xargs -r apt-mark manual \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && npm cache clear --force \
    && chown -R rocketchat:rocketchat /app \
    && rm -rf /var/lib/apt/lists/*

FROM preps as final

#COPY --from=preps /app /app

USER rocketchat

VOLUME /app/uploads/

WORKDIR /app/bundle

# needs a mongoinstance - defaults to container linking with alias 'mongo'
ENV DEPLOY_METHOD=docker \
    NODE_ENV=production \
    MONGO_URL=mongodb://mongo:27017/rocketchat \
    HOME=/tmp \
    PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    Accounts_AvatarStorePath=/app/uploads

EXPOSE 3000

CMD ["node", "main.js"]
