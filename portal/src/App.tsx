import { useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  BookOpenText,
  Check,
  Code2,
  Copy,
  ExternalLink,
  FileText,
  GitBranch,
  Moon,
  Server,
  Sun,
  Terminal,
} from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";

type ServiceItem = {
  id: string;
  title: string;
  url: string;
  description: string;
  protection?: string;
};

type SkillItem = {
  id: string;
  title: string;
  path: string;
  description: string;
  installCommand: string;
  sourceUrl?: string;
  tags: string[];
};

type SkillSource = {
  raw: string;
  frontmatter: Record<string, string>;
  body: string;
};

type Tab = "services" | "skills";
type Theme = "dark" | "light";

export default function App() {
  const [tab, setTab] = useState<Tab>("services");
  const [theme, setTheme] = useState<Theme>("dark");

  useEffect(() => {
    document.documentElement.classList.toggle("dark", theme === "dark");
    document.documentElement.classList.toggle("light", theme === "light");
  }, [theme]);

  return (
    <main className="min-h-screen">
      <div className="border-b bg-card/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-5 py-5 md:flex-row md:items-center md:justify-between md:px-8">
          <div className="flex flex-col gap-1">
            <p className="text-xs font-semibold uppercase text-muted-foreground">vps-infra</p>
            <h1 className="text-2xl font-bold tracking-normal">공용 인프라 포털</h1>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Tabs value={tab} onValueChange={(value) => setTab(value as Tab)}>
              <TabsList>
                <TabsTrigger value="services">
                  <Server data-icon="inline-start" />
                  Services
                </TabsTrigger>
                <TabsTrigger value="skills">
                  <BookOpenText data-icon="inline-start" />
                  Skills
                </TabsTrigger>
              </TabsList>
            </Tabs>
            <Button
              onClick={() => setTheme((current) => (current === "dark" ? "light" : "dark"))}
              size="icon"
              title={theme === "dark" ? "Light mode" : "Dark mode"}
              variant="outline"
            >
              {theme === "dark" ? <Sun /> : <Moon />}
            </Button>
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-6xl px-5 py-6 md:px-8">
        {tab === "services" ? <ServicesView /> : <SkillsView />}
      </div>
    </main>
  );
}

function ServicesView() {
  const [services, setServices] = useState<ServiceItem[]>([]);

  useEffect(() => {
    fetch("/config/services.json")
      .then((res) => res.json())
      .then(setServices)
      .catch(() => setServices([]));
  }, []);

  return (
    <section aria-labelledby="services-title" className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <h2 id="services-title" className="text-xl font-semibold tracking-normal">
          Services
        </h2>
        <p className="text-sm text-muted-foreground">현재 repo에 구현된 public entrypoint만 표시.</p>
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        {services.map((service) => (
          <Card key={service.id} className="min-w-0 border-border/80 bg-card">
            <CardHeader>
              <div className="flex items-start justify-between gap-3">
                <CardTitle className="text-base">{service.title}</CardTitle>
                {service.protection ? <Badge variant="secondary">{service.protection}</Badge> : null}
              </div>
              <CardDescription>{service.description}</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              <a
                className="break-all text-sm font-medium text-primary underline-offset-4 hover:underline"
                href={service.url}
                rel="noreferrer"
                target="_blank"
              >
                {service.url}
              </a>
              <Button asChild size="sm" variant="outline">
                <a href={service.url} rel="noreferrer" target="_blank">
                  <ExternalLink data-icon="inline-start" />
                  Open
                </a>
              </Button>
            </CardContent>
          </Card>
        ))}
      </div>
    </section>
  );
}

function SkillsView() {
  const [items, setItems] = useState<SkillItem[]>([]);
  const [selectedId, setSelectedId] = useState<string>("");
  const [source, setSource] = useState<SkillSource | null>(null);
  const selected = useMemo(() => items.find((item) => item.id === selectedId), [items, selectedId]);

  useEffect(() => {
    fetch("/skills/index.json")
      .then((res) => res.json())
      .then((next: SkillItem[]) => {
        setItems(next);
        setSelectedId(next[0]?.id ?? "");
      })
      .catch(() => setItems([]));
  }, []);

  useEffect(() => {
    if (!selected) return;
    fetch(selected.path)
      .then((res) => res.text())
      .then((raw) => setSource(parseSkill(raw)))
      .catch(() => setSource(null));
  }, [selected]);

  return (
    <section aria-labelledby="skills-title" className="grid gap-4 lg:grid-cols-[280px_1fr]">
      <Card className="border-border/80 bg-card">
        <CardHeader>
          <CardTitle id="skills-title" className="text-lg">
            Skills
          </CardTitle>
          <CardDescription>원문 확인과 복사용 curated list.</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col gap-2">
            {items.map((item) => (
              <Button
                className={cn(
                  "h-auto justify-start rounded-md px-3 py-2 text-left",
                  item.id === selectedId && "bg-accent text-accent-foreground hover:bg-accent/90",
                )}
                key={item.id}
                onClick={() => setSelectedId(item.id)}
                variant="ghost"
              >
                <span className="flex min-w-0 flex-col gap-1">
                  <span className="truncate font-semibold">{item.title}</span>
                  <span className="line-clamp-2 text-xs opacity-75">{item.description}</span>
                </span>
              </Button>
            ))}
          </div>
        </CardContent>
      </Card>

      <Card className="min-w-0 border-border/80 bg-card">
        {selected && source ? (
          <>
            <CardHeader className="gap-4">
              <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                <div className="flex min-w-0 flex-col gap-2">
                  <div className="flex flex-wrap gap-1.5">
                    {selected.tags.map((tag) => (
                      <Badge key={tag} variant="outline">
                        {tag}
                      </Badge>
                    ))}
                  </div>
                  <div className="flex flex-col gap-1">
                    <CardTitle className="text-xl">{selected.title}</CardTitle>
                    <CardDescription>{selected.description}</CardDescription>
                  </div>
                  {selected.sourceUrl ? <SourceLink url={selected.sourceUrl} /> : null}
                </div>
                <div className="flex flex-wrap gap-2">
                  <CopyButton text={source.raw}>Original</CopyButton>
                  <CopyButton text={source.body}>Body</CopyButton>
                </div>
              </div>
            </CardHeader>

            <CardContent className="flex flex-col gap-4">
              <InstallCommand command={selected.installCommand} />
              <MetadataGrid values={source.frontmatter} />

              <Tabs defaultValue="preview">
                <TabsList>
                  <TabsTrigger value="preview">
                    <FileText data-icon="inline-start" />
                    Preview
                  </TabsTrigger>
                  <TabsTrigger value="raw">
                    <Code2 data-icon="inline-start" />
                    Raw
                  </TabsTrigger>
                </TabsList>
                <TabsContent value="preview">
                  <ScrollArea className="h-[560px] rounded-lg border bg-card">
                    <MarkdownPreview body={source.body} />
                  </ScrollArea>
                </TabsContent>
                <TabsContent value="raw">
                  <ScrollArea className="h-[560px] rounded-lg border border-border bg-code">
                    <pre className="whitespace-pre-wrap break-words p-4 font-mono text-sm text-code-foreground">{source.raw}</pre>
                  </ScrollArea>
                </TabsContent>
              </Tabs>
            </CardContent>
          </>
        ) : (
          <CardContent className="flex min-h-64 items-center justify-center text-sm text-muted-foreground">
            Skill 없음.
          </CardContent>
        )}
      </Card>
    </section>
  );
}

function SourceLink({ url }: { url: string }) {
  const sourceLabel = url.replace(/^https?:\/\//, "");

  return (
    <a
      className="inline-flex w-fit items-center gap-1.5 rounded-full border border-border px-3 py-1 text-xs font-medium text-muted-foreground transition-colors hover:text-foreground"
      href={url}
      rel="noreferrer"
      target="_blank"
    >
      <GitBranch />
      <span>Source: {sourceLabel}</span>
      <ExternalLink />
    </a>
  );
}

function InstallCommand({ command }: { command: string }) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setState("copied");
    } catch {
      setState("failed");
    }
    window.setTimeout(() => setState("idle"), 1400);
  }

  return (
    <div className="overflow-hidden rounded-lg border border-border bg-code text-code-foreground">
      <div className="flex items-center justify-between border-b border-border px-4 py-2 text-xs text-code-muted">
        <span className="inline-flex items-center gap-1.5">
          <Terminal />
          install
        </span>
        <Button onClick={copy} size="sm" title="Copy install command" variant="ghost">
          {state === "copied" ? <Check data-icon="inline-start" /> : <Copy data-icon="inline-start" />}
          {state === "copied" ? "Copied" : state === "failed" ? "Failed" : "Copy"}
        </Button>
      </div>
      <div className="flex min-w-0 items-center gap-3 px-4 py-5 font-mono text-sm md:text-base">
        <span className="text-code-muted">$</span>
        <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap">{command}</code>
      </div>
    </div>
  );
}

function CopyButton({ children, text }: { children: string; text: string }) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setState("copied");
    } catch {
      setState("failed");
    }
    window.setTimeout(() => setState("idle"), 1400);
  }

  return (
    <Button onClick={copy} size="sm" title={state === "failed" ? "복사 실패. Raw 탭에서 수동 복사." : children} variant="outline">
      {state === "copied" ? (
        <Check data-icon="inline-start" />
      ) : state === "failed" ? (
        <AlertTriangle data-icon="inline-start" />
      ) : (
        <Copy data-icon="inline-start" />
      )}
      {state === "copied" ? "Copied" : state === "failed" ? "Failed" : children}
    </Button>
  );
}

function MetadataGrid({ values }: { values: Record<string, string> }) {
  const entries = Object.entries(values);

  if (entries.length === 0) return null;

  return (
    <div className="rounded-lg border border-border">
      <div className="grid md:grid-cols-2">
        {entries.map(([key, value], index) => (
          <div className="flex min-w-0 flex-col gap-1 p-3" key={key}>
            {index > 0 ? <Separator className="md:hidden" /> : null}
            <dt className="text-xs font-semibold uppercase text-muted-foreground">{key}</dt>
            <dd className="break-words text-sm">{value}</dd>
          </div>
        ))}
      </div>
    </div>
  );
}

function parseSkill(raw: string): SkillSource {
  if (!raw.startsWith("---")) {
    return { raw, frontmatter: {}, body: raw.trim() };
  }

  const end = raw.indexOf("\n---", 3);
  if (end === -1) {
    return { raw, frontmatter: {}, body: raw.trim() };
  }

  const frontmatterText = raw.slice(3, end).trim();
  const body = raw.slice(end + 4).trim();
  const frontmatter = parseFrontmatter(frontmatterText);

  return { raw, frontmatter, body };
}

function parseFrontmatter(text: string): Record<string, string> {
  const result: Record<string, string> = {};
  let currentKey = "";
  let collectingBlock = false;

  for (const line of text.split("\n")) {
    const keyValue = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (keyValue) {
      currentKey = keyValue[1];
      const value = keyValue[2].trim();
      collectingBlock = value === ">" || value === ">-" || value === "|" || value === "|-";
      result[currentKey] = collectingBlock ? "" : value.replace(/^["']|["']$/g, "");
      continue;
    }

    if (collectingBlock && currentKey && line.startsWith(" ")) {
      result[currentKey] = `${result[currentKey]} ${line.trim()}`.trim();
    }
  }

  return result;
}

function MarkdownPreview({ body }: { body: string }) {
  const blocks = body.split(/\n{2,}/);

  return (
    <div className="flex flex-col gap-4 p-4">
      {blocks.map((block, index) => {
        if (block.startsWith("```")) {
          return (
            <pre className="overflow-x-auto whitespace-pre-wrap rounded-lg bg-code p-4 font-mono text-sm text-code-foreground" key={index}>
              {block.replace(/^```\w*\n?|\n?```$/g, "")}
            </pre>
          );
        }
        if (block.startsWith("# ")) return <h1 className="text-2xl font-bold tracking-normal" key={index}>{block.slice(2)}</h1>;
        if (block.startsWith("## ")) return <h2 className="border-t pt-4 text-xl font-semibold tracking-normal" key={index}>{block.slice(3)}</h2>;
        if (block.startsWith("### ")) return <h3 className="text-base font-semibold" key={index}>{block.slice(4)}</h3>;
        if (block.startsWith("- ")) {
          return (
            <ul className="flex list-disc flex-col gap-1 pl-5 text-sm text-muted-foreground" key={index}>
              {block.split("\n").map((line) => (
                <li key={line}>{line.replace(/^- /, "")}</li>
              ))}
            </ul>
          );
        }
        return (
          <p className="whitespace-pre-wrap text-sm leading-6 text-muted-foreground" key={index}>
            {block}
          </p>
        );
      })}
    </div>
  );
}
