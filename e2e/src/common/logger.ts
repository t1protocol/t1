import { Logger as LoggerClass, createLogger, transports, format } from "winston";

export function createWinstonLogger(name: string) : LoggerClass  {
    const { align, combine, colorize, timestamp, printf, errors, splat, label } = format;

    return createLogger({
        level: "info",
        format: combine(
            timestamp(),
            errors({ stack: true }),
            splat(),
            label({ label: name }),
            printf(({ timestamp, level, label, message, stack, ...metadata }) => {
                let str = `time=${timestamp} level=${level.toUpperCase()} message=${message}`;

                return colorize().colorize(level, str);
            }),
            align(),
        ),
        transports: [new transports.Console()]
    });
}