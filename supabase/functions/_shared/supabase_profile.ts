export type SupabaseProfile = {
  gotrue_id?: unknown;
  primary_email?: unknown;
  email?: unknown;
  username?: unknown;
  name?: unknown;
  full_name?: unknown;
  user_metadata?: Record<string, unknown> | null;
  identities?: Array<{ identity_data?: Record<string, unknown> | null }> | null;
};

function cleanString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function displayNameFromSupabaseProfile(
  profile: SupabaseProfile | null | undefined,
): string | null {
  if (!profile) return null;

  const direct = [
    profile.primary_email,
    profile.email,
    profile.username,
    profile.name,
    profile.full_name,
  ];
  for (const value of direct) {
    const cleaned = cleanString(value);
    if (cleaned) return cleaned;
  }

  const metadata = profile.user_metadata;
  if (metadata) {
    for (
      const key of ["email", "primary_email", "full_name", "name", "username"]
    ) {
      const cleaned = cleanString(metadata[key]);
      if (cleaned) return cleaned;
    }
  }

  for (const identity of profile.identities ?? []) {
    const data = identity.identity_data;
    if (!data) continue;
    for (
      const key of ["email", "primary_email", "full_name", "name", "username"]
    ) {
      const cleaned = cleanString(data[key]);
      if (cleaned) return cleaned;
    }
  }

  return null;
}
