FROM docker.io/library/golang:1.26-bookworm AS b
WORKDIR /s
COPY main.go .
RUN go mod init fwd >/dev/null 2>&1 && CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o /fwd .
FROM scratch
COPY --from=b /fwd /fwd
USER 65532:65532
ENTRYPOINT ["/fwd"]
