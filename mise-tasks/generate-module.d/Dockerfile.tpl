# Build locally first: mise run //modules/template:build
FROM gcr.io/distroless/base-debian12:nonroot
COPY dist/template /template
EXPOSE 8081 8082
ENTRYPOINT ["/template"]
CMD ["service"]
