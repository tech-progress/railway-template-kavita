FROM sigoden/dufs:v0.47.0@sha256:e5152c04e41d5a9d785546278b632bf035c8a08c52d7e8d35f4b59681f5ff35a AS dufs
FROM jvmilazz0/kavita:0.9.1@sha256:31181a32f0dda73cae68721867028a7253d57881b58bea5754cd9e578e75421a
COPY --from=dufs /bin/dufs /usr/local/bin/dufs
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint
# Kavita reads its state from /kavita/config. Point it at the Railway volume so
# configuration and the uploaded library share the service's single volume.
RUN chmod 0755 /usr/local/bin/railway-entrypoint \
 && rm -rf /kavita/config \
 && ln -s /data/config /kavita/config
ENV KAVITA_DATA_DIR=/data UPLOAD_PORT=5001
EXPOSE 5000 5001
ENTRYPOINT ["/usr/local/bin/railway-entrypoint"]
