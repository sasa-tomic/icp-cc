export interface Env {
  DB: D1Database;
  ENVIRONMENT: string;
  TEST_DB_NAME?: string;
}

export interface Script {
  id: string;
  title: string;
  description: string;
  category: string;
  tags?: string[];
  luaSource: string;
  authorName: string;
  authorId: string;
  authorPrincipal?: string; // ICP principal of the script author
  authorPublicKey?: string; // Public key for signature verification
  uploadSignature?: string; // Signature of the initial upload payload
  canisterIds?: string[];
  iconUrl?: string;
  screenshots?: string[];
  version: string;
  compatibility?: string;
  price: number;
  isPublic: boolean;
  downloads: number;
  rating: number;
  reviewCount: number;
  createdAt: string;
  updatedAt: string;
  author?: Author;
  reviews?: Review[];
}

export interface Author {
  id: string;
  username: string;
  displayName: string;
  avatar?: string;
  isVerifiedDeveloper: boolean;
}

export interface User {
  id: string;
  email?: string;
  name: string;
  isVerifiedDeveloper: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface Review {
  id: string;
  scriptId: string;
  userId: string;
  rating: number;
  comment?: string;
  createdAt: string;
  updatedAt: string;
}

export interface Purchase {
  id: string;
  scriptId: string;
  userId: string;
  price: number;
  purchaseDate: string;
}

export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  details?: string;
}

export interface PaginatedResponse<T> extends ApiResponse<T> {
  total?: number;
  hasMore?: boolean;
}