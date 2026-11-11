import { credentialExchange } from "@/lib/auth-route";

export async function POST(request: Request) {
  return credentialExchange(request, "auth/register");
}
