// Wire schema for GET /v1/sessions. Mirrors happy-server's sessionRoutes
// response. Fields marked "encrypted" are base64-encoded bundles; decoding
// happens in Stage service layer (dataEncryptionKey via crypto_box; then
// metadata/agentState via AES-256-GCM — the latter lands in PoC-A3).

export interface Session {
  id: string;
  seq: number;
  createdAt: number;
  updatedAt: number;
  active: boolean;
  activeAt: number;
  /** base64 AES-GCM ciphertext of Metadata JSON. */
  metadata: string;
  metadataVersion: number;
  /** base64 AES-GCM ciphertext of AgentState JSON. null if never populated. */
  agentState: string | null;
  agentStateVersion: number;
  /** base64 box bundle wrapping the per-session 32-byte AES-GCM key. */
  dataEncryptionKey: string | null;
  /** Always null in /v1/sessions; populated only via realtime updates. */
  lastMessage: null;
}

export interface SessionListResponse {
  sessions: Session[];
}
