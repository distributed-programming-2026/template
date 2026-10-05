package event

import "github.com/distributed-programming-2026/go-sdk/pkg/amqp"

func DomainExchange() *amqp.ExchangeConfig {
	return &amqp.ExchangeConfig{
		Name:    "domain-event",
		Kind:    "topic",
		Durable: true,
	}
}

func DomainDeadLetterExchange() *amqp.ExchangeConfig {
	return &amqp.ExchangeConfig{
		Name:    "domain-event.dead",
		Kind:    "direct",
		Durable: true,
	}
}
