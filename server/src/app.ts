import Fastify from "fastify";
import { registerApiKeyAuth } from "./auth.js";
import { registerRoutes } from "./routes.js";
import type { ServerConfig } from "./config.js";
import type { ModaDatabase } from "./database.js";

type BuildAppOptions = {
  config: ServerConfig;
  database: ModaDatabase;
};

export function buildApp({ config, database }: BuildAppOptions) {
  const app = Fastify({
    logger: true
  });

  app.setErrorHandler((error, _request, reply) => {
    const message = error instanceof Error ? error.message : "Unknown server error.";
    const statusCode = message.includes("must") || message.includes("Invalid") ? 400 : 500;
    reply.code(statusCode).send({
      error: statusCode === 400 ? "Bad Request" : "Internal Server Error",
      message
    });
  });

  registerApiKeyAuth(app, config.apiKey);
  registerRoutes(app, { database });

  return app;
}
