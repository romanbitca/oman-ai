import { WorkspaceSwitcher } from '@/components/workspace-switcher'

export default function App(): JSX.Element {
  return (
    <div className="flex h-screen w-screen flex-col bg-background text-foreground">
      <header className="flex items-center border-b border-border px-3 py-2">
        <WorkspaceSwitcher />
      </header>
      <main className="flex flex-1 items-center justify-center">
        <h1 className="text-4xl font-medium tracking-tight">oman</h1>
      </main>
    </div>
  )
}
