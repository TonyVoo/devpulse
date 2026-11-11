import { Shell } from "@/components/shell/shell";
import { getMe } from "@/lib/server-api";

export default async function AppLayout({ children }: LayoutProps<"/">) {
  const me = await getMe();
  return (
    <Shell user={{ name: me.display_name, email: me.email }} orgs={me.memberships}>
      {children}
    </Shell>
  );
}
