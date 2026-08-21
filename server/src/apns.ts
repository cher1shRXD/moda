import crypto from "node:crypto";
import fs from "node:fs";
import http2 from "node:http2";
import type { ServerConfig } from "./config.js";
import type { DeviceTokenRecord } from "./types.js";

type ApnsPayload = {
  title: string;
  body: string;
  data?: Record<string, string | number | boolean | null>;
};

type ApnsSendResult = {
  token: string;
  sent: boolean;
  status?: number;
  reason?: string;
};

export class ApnsConfigState {
  constructor(private readonly config: ServerConfig["apns"]) {}

  isConfigured(): boolean {
    return Boolean(
      this.config.teamId &&
      this.config.keyId &&
      this.config.bundleId &&
      this.config.privateKeyPath
    );
  }

  status() {
    return {
      configured: this.isConfigured(),
      bundleId: this.config.bundleId
    };
  }
}

export class ApnsClient {
  private cachedJwt: { token: string; issuedAt: number } | undefined;

  constructor(private readonly config: ServerConfig["apns"]) {}

  isConfigured(): boolean {
    return Boolean(
      this.config.teamId &&
      this.config.keyId &&
      this.config.bundleId &&
      this.config.privateKeyPath
    );
  }

  async send(deviceToken: DeviceTokenRecord, payload: ApnsPayload): Promise<ApnsSendResult> {
    if (!this.isConfigured()) {
      return {
        token: deviceToken.token,
        sent: false,
        reason: "APNs is not configured."
      };
    }

    const host = deviceToken.environment === "production"
      ? "api.push.apple.com"
      : "api.sandbox.push.apple.com";
    const client = http2.connect(`https://${host}`);

    try {
      const body = JSON.stringify({
        aps: {
          alert: {
            title: payload.title,
            body: payload.body
          },
          sound: "default"
        },
        moda: payload.data ?? {}
      });

      const result = await new Promise<ApnsSendResult>((resolve, reject) => {
        const request = client.request({
          ":method": "POST",
          ":path": `/3/device/${deviceToken.token}`,
          authorization: `bearer ${this.jwt()}`,
          "apns-topic": this.config.bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10"
        });

        let responseBody = "";
        let status = 0;

        request.setEncoding("utf8");
        request.on("response", (headers) => {
          status = Number(headers[":status"] ?? 0);
        });
        request.on("data", (chunk: string) => {
          responseBody += chunk;
        });
        request.on("error", reject);
        request.on("end", () => {
          if (status >= 200 && status < 300) {
            resolve({ token: deviceToken.token, sent: true, status });
            return;
          }

          resolve({
            token: deviceToken.token,
            sent: false,
            status,
            reason: parseApnsReason(responseBody)
          });
        });
        request.end(body);
      });

      return result;
    } finally {
      client.close();
    }
  }

  private jwt(): string {
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (this.cachedJwt && nowSeconds - this.cachedJwt.issuedAt < 3_000) {
      return this.cachedJwt.token;
    }

    const header = base64Url(JSON.stringify({
      alg: "ES256",
      kid: this.config.keyId
    }));
    const payload = base64Url(JSON.stringify({
      iss: this.config.teamId,
      iat: nowSeconds
    }));
    const signingInput = `${header}.${payload}`;
    const privateKey = fs.readFileSync(this.config.privateKeyPath!, "utf8");
    const signature = crypto.createSign("SHA256").update(signingInput).sign(privateKey);
    const token = `${signingInput}.${base64Url(derToJose(signature))}`;

    this.cachedJwt = {
      token,
      issuedAt: nowSeconds
    };

    return token;
  }
}

function parseApnsReason(body: string): string {
  if (!body) {
    return "APNs request failed.";
  }

  try {
    const parsed = JSON.parse(body) as { reason?: unknown };
    return typeof parsed.reason === "string" ? parsed.reason : body;
  } catch {
    return body;
  }
}

function base64Url(value: string | Buffer): string {
  return Buffer.from(value)
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function derToJose(signature: Buffer): Buffer {
  let offset = 2;
  if (signature[1] & 0x80) {
    offset = 2 + (signature[1] & 0x7f);
  }

  if (signature[offset] !== 0x02) {
    throw new Error("Invalid ECDSA signature.");
  }

  let rLength = signature[offset + 1];
  offset += 2;

  if (signature[offset] === 0x00) {
    offset += 1;
    rLength -= 1;
  }

  const r = signature.subarray(offset, offset + rLength);
  offset += rLength;

  if (signature[offset] !== 0x02) {
    throw new Error("Invalid ECDSA signature.");
  }

  let sLength = signature[offset + 1];
  offset += 2;

  if (signature[offset] === 0x00) {
    offset += 1;
    sLength -= 1;
  }

  const s = signature.subarray(offset, offset + sLength);
  return Buffer.concat([leftPad(r, 32), leftPad(s, 32)]);
}

function leftPad(value: Buffer, length: number): Buffer {
  if (value.length === length) {
    return value;
  }

  if (value.length > length) {
    return value.subarray(value.length - length);
  }

  return Buffer.concat([Buffer.alloc(length - value.length), value]);
}
