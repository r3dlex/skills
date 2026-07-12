# When to Mock

Mock at **system boundaries** only:

- External APIs (payment, email, etc.)
- Databases (sometimes - prefer test DB)
- Time/randomness
- File system (sometimes)

Don't mock:

- Your own classes/modules
- Internal collaborators
- Anything you control

## LLM harness boundaries

**Mock the network, not the model wrapper.** Intercept raw HTTP requests and
return provider-shaped responses so authentication, serialization, status-code,
retry, token-metadata, and finish-reason handling are exercised together.

- Keep fixture-driven raw JSON responses captured from real provider shapes,
  with secrets and user data removed.
- Keep routing, schema validation, markdown-fence parsing, retry/backoff decisions,
  and banned-topic guards deterministic in unit tests.
- Keep probabilistic model quality and live LLM-as-a-judge calls in integration
  or eval pipelines; unit-test their orchestration with raw HTTP fixtures.
- For retry tests, inject or fake the clock so exponential backoff is verified
  without sleeping.

## Designing for Mockability

At system boundaries, design interfaces that are easy to mock:

**1. Use dependency injection**

Pass external dependencies in rather than creating them internally:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

**2. Prefer SDK-style interfaces over generic fetchers**

Create specific functions for each external operation instead of one generic function with conditional logic:

```typescript
// GOOD: Each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: Mocking requires conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach means:
- Each mock returns one specific shape
- No conditional logic in test setup
- Easier to see which endpoints a test exercises
- Type safety per endpoint
