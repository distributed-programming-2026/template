openapi: 3.0.0
info:
  version: 1.0.0
  title: Template service public API
  x-api-identifier: templatepublicapi
paths:
  /api/public/v1/echo:
    post:
      operationId: echo
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/echoRequest"
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/echoResponseData"
components:
  schemas:
    echoRequest:
      type: object
      properties:
        body:
          type: string
      required:
        - body
    echoResponseData:
      type: object
      properties:
        operationID:
          type: string
      required:
        - operationID
