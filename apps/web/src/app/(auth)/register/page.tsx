import type { Metadata } from "next";

import { AuthForm } from "@/components/auth/auth-form";
import { getT } from "@/lib/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("auth.createAccount") };
}

export default function RegisterPage() {
  return <AuthForm mode="register" next="/orgs" />;
}
