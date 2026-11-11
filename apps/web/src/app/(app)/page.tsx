import { redirect } from "next/navigation";

import { getMe } from "@/lib/server-api";

export default async function Home() {
  const me = await getMe();
  redirect(me.memberships.length > 0 ? `/o/${me.memberships[0].id}` : "/orgs");
}
