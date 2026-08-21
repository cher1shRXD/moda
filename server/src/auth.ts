import type { FastifyInstance } from "fastify";

export function registerApiKeyAuth(app: FastifyInstance, apiKey: string): void {
  app.addHook("onRequest", async (request, reply) => {
    if (request.url === "/health") {
      return;
    }

    const providedKey = request.headers["x-moda-api-key"];
    if (providedKey !== apiKey) {
      await reply.code(401).send({
        error: "Unauthorized",
        message: "Missing or invalid X-MODA-API-KEY header."
      });
    }
  });
}
