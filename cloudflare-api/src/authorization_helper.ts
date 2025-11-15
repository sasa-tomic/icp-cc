import { TestIdentity, JsonResponse } from './utils';

/**
 * Simplified authorization helper for development/testing environments
 * Consolidates authorization logic used across multiple endpoints
 */
export class AuthorizationHelper {
  /**
   * Validates authorization for script operations
   * @param signature - The authorization signature
   * @param authorPublicKey - The author's public key
   * @param authorPrincipal - The author's principal
   * @returns true if authorization is valid
   */
  static isValidAuthorization(
    signature: string | undefined,
    authorPublicKey: string | undefined,
    authorPrincipal: string | undefined
  ): boolean {
    // Test token authorization
    if (signature === 'test-auth-token') {
      return true;
    }

    // Test identity authorization (development/testing)
    if (
      authorPublicKey === TestIdentity.getPublicKey() &&
      authorPrincipal === TestIdentity.getPrincipal()
    ) {
      return true;
    }

    return false;
  }

  /**
   * Creates a standardized unauthorized response
   * @param message - Optional custom error message
   * @returns 401 JSON error response
   */
  static createUnauthorizedResponse(message = 'Invalid authorization'): Response {
    return JsonResponse.error(message, 401);
  }

  /**
   * Validates authorization and creates response if invalid
   * @param signature - The authorization signature
   * @param authorPublicKey - The author's public key
   * @param authorPrincipal - The author's principal
   * @param customMessage - Optional custom error message
   * @returns null if authorization is valid, 401 response if invalid
   */
  static validateAndRespond(
    signature: string | undefined,
    authorPublicKey: string | undefined,
    authorPrincipal: string | undefined,
    customMessage?: string
  ): Response | null {
    if (!this.isValidAuthorization(signature, authorPublicKey, authorPrincipal)) {
      return this.createUnauthorizedResponse(customMessage);
    }
    return null;
  }

  /**
   * Validates required authorization fields are present
   * @param signature - The authorization signature
   * @param authorPrincipal - The author's principal
   * @returns true if both fields are present
   */
  static hasRequiredAuthFields(
    signature: string | undefined,
    authorPrincipal: string | undefined
  ): boolean {
    return !!(signature && authorPrincipal);
  }

  /**
   * Creates response for missing authorization fields
   * @returns 401 JSON error response
   */
  static createMissingAuthResponse(): Response {
    return JsonResponse.error('Missing signature or author principal', 401);
  }
}