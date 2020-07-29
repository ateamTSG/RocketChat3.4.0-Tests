# The tag here should match the Meteor version of your app, per .meteor/release
FROM geoffreybooth/meteor-base:1.10.2 as meteorbase

# Copy app source into container
COPY . $APP_SOURCE_FOLDER/

# Instll npm dependencies
WORKDIR $APP_SOURCE_FOLDER
RUN meteor npm install

# Build meteor bundle
RUN mkdir --parents "$APP_BUNDLE_FOLDER"
RUN meteor build --directory "$APP_BUNDLE_FOLDER" --server-only

#RUN bash $SCRIPTS_FOLDER/build-app-npm-dependencies.sh to perform meteor npm install 
#RUN bash "$SCRIPTS_FOLDER"/build-app-npm-dependencies.sh

#RUN bash $SCRIPTS_FOLDER/build-meteor-bundle.sh to perform meteor build
#RUN bash "$SCRIPTS_FOLDER"/build-meteor-bundle.sh

# Use the specific version of Node expected by your Meteor release, per https://docs.meteor.com/changelog.html; this is expected for Meteor 1.10.2
FROM node:12.16.1-buster-slim as rocketbuild
    
ENV APP_BUNDLE_FOLDER /opt/bundle
ENV SCRIPTS_FOLDER /docker

# Copy in entrypoint
COPY --from=meteorbase $SCRIPTS_FOLDER $SCRIPTS_FOLDER/

# Copy in app bundle
COPY --from=meteorbase "$APP_BUNDLE_FOLDER"/bundle "$APP_BUNDLE_FOLDER"/bundle/

RUN groupadd -g 65533 -r rocketchat \
    && useradd -u 65533 -r -g rocketchat rocketchat \
    && mkdir -p /$APP_BUNDLE_FOLDER/uploads \
    && chown rocketchat:rocketchat /"$APP_BUNDLE_FOLDER"/uploads \
    && apt-get update \
    && apt-get install -y --no-install-recommends fontconfig \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

#RUN bash "$SCRIPTS_FOLDER"/build-meteor-npm-dependencies.sh

# Start app
RUN aptMark="$(apt-mark showmanual)" \
    && apt-get install -y --no-install-recommends g++ make python ca-certificates \
    && cd /"$APP_BUNDLE_FOLDER"/bundle/programs/server \
    && npm install \
    && apt-mark auto '.*' > /dev/null \
    && apt-mark manual "$aptMark" > /dev/null \
    && find /usr/local -type f -executable -exec ldd '{}' ';' \
       | awk '/=>/ { print $(NF-1) }' \
       | sort -u \
       | xargs -r dpkg-query --search \
       | cut -d: -f1 \
       | sort -u \
       | xargs -r apt-mark manual \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && npm cache clear --force \
    && chown -R rocketchat:rocketchat /"$APP_BUNDLE_FOLDER"

USER rocketchat

VOLUME /$APP_BUNDLE_FOLDER/uploads

WORKDIR /$APP_BUNDLE_FOLDER/bundle

# needs a mongoinstance - defaults to container linking with alias 'mongo'
ENV DEPLOY_METHOD=docker \
    NODE_ENV=production \
    MONGO_URL=mongodb://mongo:27017/rocketchat \
    HOME=/tmp \
    PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    Accounts_AvatarStorePath=/$APP_BUNDLE_FOLDER/uploads

EXPOSE 3000

CMD ["node", "main.js"]
