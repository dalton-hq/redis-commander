FROM alpine:3.24.4

WORKDIR /redis-commander

# optional build arg to let the hardening process remove all package manager (apk, npm, yarn) too to not allow
# installation of packages anymore, default: do not remove "apk" to allow others to use this as a base image
# for own images
ARG REMOVE_APK=0

ENV SERVICE_USER=redis
ENV HOME=/redis-commander
ENV NODE_ENV=production

# only single copy command for most parts as other files are ignored via .dockerignore
# to create less layers
COPY . .

# for Openshift compatibility set project config dir itself group root and make it group writeable
RUN  apk update \
  && apk upgrade \
  && apk add --no-cache ca-certificates=20261020-r0 dumb-init=1.2.5-r4 sed=4.9-r2 jq=1.8.2-r0 moreutils=0.70-r1 nodejs-current=26.13.1-r0 c-ares=1.34.9-r0 npm=11.12.1-r0 yarn=1.22.22-r1 icu-libs=78.1-r0 icu-data-en=78.1-r0 \
  && update-ca-certificates \
  && echo -e "\n---- Create runtime user and fix file access rights ----------" \
  && adduser "${SERVICE_USER}" -h "${HOME}" -G root -S -u 10000 \
  && chown -R root:root "${HOME}" \
  && chown -R "${SERVICE_USER}" "${HOME}/config" \
  && chmod g+w "${HOME}/config" \
  && chmod ug+r,o-rwx "${HOME}"/config/*.json \
  && echo -e "\n---- Check config file syntax --------------------------------" \
  && for i in "${HOME}"/config/*.json; do echo "checking config file $i"; cat "$i" | jq empty; ret=$?; if [ $ret -ne 0 ]; then exit $ret; fi; done \
  && echo -e "\n---- Installing app ------------------------------------------" \
  && npm install --global npm@12.2.2 \
  && npm ci --include=dev \
  && npm run build \
  && npm run sbom \
  && npm prune --omit=dev \
  && echo -e "\n---- Cleanup and hardening -----------------------------------" \
  && "${HOME}/docker/harden.sh" \
  && rm -rf /tmp/* /root/.??* /root/cache /var/cache/apk/*

USER 10000

HEALTHCHECK --interval=1m --timeout=2s CMD ["/redis-commander/bin/healthcheck.js"]

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/redis-commander/docker/entrypoint.sh"]

EXPOSE 8081
