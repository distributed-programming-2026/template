kind: gateway/service/v1
name: template
weight: 100
routes:
  - pattern: '^/template/api/.*$'
    rewrite:
      old: '^/template/(.*)$'
      new: '/$1'
    target: template-service:8082
