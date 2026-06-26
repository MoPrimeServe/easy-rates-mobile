/**
 * ApiError — the throwable that maps to the conventions §3 standard error codes.
 * Throw these anywhere; the global error middleware serialises them into the
 * `{ data: null, error }` envelope with the right HTTP status.
 */
export class ApiError extends Error {
  readonly code: string;
  readonly httpStatus: number;
  readonly details: Record<string, unknown>;

  constructor(
    code: string,
    httpStatus: number,
    message: string,
    details: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = "ApiError";
    this.code = code;
    this.httpStatus = httpStatus;
    this.details = details;
    Object.setPrototypeOf(this, ApiError.prototype);
  }

  // ---- Standard error codes (conventions §3) -------------------------------

  static validation(
    fields: Record<string, string>,
    message = "One or more fields are invalid.",
  ): ApiError {
    return new ApiError("validation_error", 400, message, { fields });
  }

  static unauthenticated(message = "Authentication required."): ApiError {
    return new ApiError("unauthenticated", 401, message);
  }

  static forbidden(message = "You are not permitted to do that."): ApiError {
    return new ApiError("forbidden", 403, message);
  }

  static notFound(message = "Resource not found."): ApiError {
    return new ApiError("not_found", 404, message);
  }

  static conflict(message = "State conflict."): ApiError {
    return new ApiError("conflict", 409, message);
  }

  static unprocessable(
    message = "Request could not be processed.",
    details: Record<string, unknown> = {},
  ): ApiError {
    return new ApiError("unprocessable", 422, message, details);
  }

  static rateLimited(
    retryAfterSeconds: number,
    message = "Too many requests.",
  ): ApiError {
    return new ApiError("rate_limit_exceeded", 429, message, {
      retryAfterSeconds,
    });
  }

  static internal(message = "An unexpected error occurred."): ApiError {
    return new ApiError("internal_server_error", 500, message);
  }
}
