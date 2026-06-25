FROM golang:1.21-alpine AS build
WORKDIR /src
COPY go.mod .
COPY main.go .
RUN go build -o /app/server .

FROM alpine:3.19
WORKDIR /app
COPY --from=build /app/server .
EXPOSE 8080
CMD ["./server"]
