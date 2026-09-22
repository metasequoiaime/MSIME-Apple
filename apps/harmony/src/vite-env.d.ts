/// <reference types="vite/client" />

declare module "*.css";

declare module "node:fs" {
  export function existsSync(path: string): boolean;
  export function readFileSync(path: string, encoding: "utf8" | "base64"): string;
  export function writeFileSync(path: string, data: string): void;
  export function rmSync(path: string, options?: { force?: boolean }): void;
  export function readdirSync(path: string): string[];
}

declare module "node:path" {
  export function join(...parts: string[]): string;
  export function dirname(path: string): string;
}

interface ImportMeta {
  dirname: string;
}
