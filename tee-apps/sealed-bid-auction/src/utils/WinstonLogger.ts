/* eslint-disable @typescript-eslint/no-explicit-any */
import { Logger as LoggerClass, type LoggerOptions, createLogger, format, transports } from "winston";

import * as dotenv from "dotenv";

dotenv.config();

export class WinstonLogger {
  private logger: LoggerClass;
  public readonly name: string;

  /**
   * Initializes a new instance of the `WinstonLogger`.
   *
   * @param {string} loggerName - The name of the logger, typically representing the class or module using this logger instance.
   * @param {LoggerOptions} [options] - Optional configuration settings for the logger, allowing customization of the logging behavior and output.
   */
  constructor(loggerName: string, options?: LoggerOptions) {
    const { align, combine, colorize, timestamp, printf, errors, splat, label } = format;

    this.logger = createLogger({
      level: process.env.LOG_LEVEL as string,
      format: combine(
        timestamp(),
        errors({ stack: true }),
        splat(),
        label({ label: loggerName }),
        printf(({ timestamp, level, label, message, stack, ...metadata }) => {
          let str = `time=${timestamp} level=${level.toUpperCase()} message=${message}`;

          str += ` | class=${label} ${this.formatMetadata(metadata)}`;

          if (stack) {
            str += ` | ${stack}`;
          }

          return colorize().colorize(level, str);
        }),
        align(),
      ),
      transports: [new transports.Console()],
      ...options,
    });
    this.name = loggerName;
  }

  /**
   * Formats metadata for logging, ensuring that non-string values are serialized for readability.
   *
   * @param {any} metadata - The metadata object to format.
   * @returns {string} A string representation of the metadata, suitable for inclusion in a log message.
   */
  private formatMetadata(metadata: any): string {
    if (typeof metadata === "string") {
      return `metadata=${metadata}`;
    }

    let str = "";

    for (const key of Object.keys(metadata)) {
      if (typeof metadata[key] === "string") {
        str += ` ${key}=${metadata[key]}`;
        continue;
      }
      str += ` ${key}=${serialize(metadata[key])}`;
    }
    return str.trim();
  }

  /**
   * Logs a message at the `info` level.
   *
   * @param {any} message - The primary log message.
   * @param {...any[]} params - Additional parameters or metadata to log alongside the message.
   */
  public info(message: any, ...params: any[]): void {
    this.logger.info(message, ...params);
  }

  /**
   * Logs a message at the `error` level.
   *
   * @param {any} message - The primary log message.
   * @param {...any[]} params - Additional parameters or metadata to log alongside the message.
   */
  public error(message: any, ...params: any[]): void {
    this.logger.error(message, ...params);
  }

  /**
   * Logs a message at the `warn` level.
   *
   * @param {any} message - The primary log message.
   * @param {...any[]} params - Additional parameters or metadata to log alongside the message.
   */
  public warn(message: any, ...params: any[]): void {
    this.logger.warn(message, ...params);
  }

  /**
   * Logs a message at the `debug` level.
   *
   * @param {any} message - The primary log message.
   * @param {...any[]} params - Additional parameters or metadata to log alongside the message.
   */
  public debug(message: any, ...params: any[]): void {
    this.logger.debug(message, ...params);
  }
}

/**
 * Stringifier that handles bigint value.
 * @param {any} value Value to stringify.
 * @returns {string} the stringified output.
 */
export function serialize(value: unknown): string {
  return JSON.stringify(value, (_, value: unknown) => (typeof value === "bigint" ? value.toString() : value));
}
