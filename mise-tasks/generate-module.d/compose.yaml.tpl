services:
  template-service:
    image: distributed-programming-template:local
    build:
      context: ./modules/template
      dockerfile: Dockerfile
    environment:
      TEMPLATE_MYSQL_ADDRESS: mysql:3306
      TEMPLATE_AMQP_URL: amqp://local:local@rabbitmq:5672/
    ports:
      - "${TEMPLATE_GRPC_PORT:-8081}:8081"
      - "${TEMPLATE_HTTP_PORT:-8082}:8082"
    depends_on:
      mysql:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy

  template-message-handler:
    image: distributed-programming-template:local
    command: [message-handler]
    environment:
      TEMPLATE_MYSQL_ADDRESS: mysql:3306
      TEMPLATE_AMQP_URL: amqp://local:local@rabbitmq:5672/
    ports:
      - "${TEMPLATE_MESSAGE_HANDLER_PORT:-8083}:8082"
    depends_on:
      template-service:
        condition: service_started
      mysql:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
