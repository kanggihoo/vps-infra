import { useEffect, useMemo, useState } from "react";

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
  tags: string[];
};

type SkillSource = {
  raw: string;
  frontmatter: Record<string, string>;
  body: string;
};

type Tab = "services" | "skills";

export default function App() {
  const [tab, setTab] = useState<Tab>("services");

  return (
    <main className="shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">vps-infra</p>
          <h1>공용 인프라 포털</h1>
        </div>
        <nav aria-label="Portal sections">
          <button className={tab === "services" ? "active" : ""} onClick={() => setTab("services")}>
            Services
          </button>
          <button className={tab === "skills" ? "active" : ""} onClick={() => setTab("skills")}>
            Skills
          </button>
        </nav>
      </header>

      {tab === "services" ? <ServicesView /> : <SkillsView />}
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
    <section className="section" aria-labelledby="services-title">
      <div className="section-header">
        <div>
          <h2 id="services-title">Services</h2>
          <p>현재 repo에 구현된 public entrypoint만 표시.</p>
        </div>
      </div>

      <div className="service-grid">
        {services.map((service) => (
          <a className="service-card" href={service.url} key={service.id} rel="noreferrer" target="_blank">
            <span className="service-title">{service.title}</span>
            <span className="service-url">{service.url}</span>
            <span className="service-desc">{service.description}</span>
            {service.protection ? <span className="pill">{service.protection}</span> : null}
          </a>
        ))}
      </div>
    </section>
  );
}

function SkillsView() {
  const [items, setItems] = useState<SkillItem[]>([]);
  const [selectedId, setSelectedId] = useState<string>("");
  const [source, setSource] = useState<SkillSource | null>(null);
  const [rawMode, setRawMode] = useState(false);
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
    <section className="section skills-layout" aria-labelledby="skills-title">
      <aside className="skill-list">
        <h2 id="skills-title">Skills</h2>
        {items.map((item) => (
          <button className={item.id === selectedId ? "selected" : ""} key={item.id} onClick={() => setSelectedId(item.id)}>
            <span>{item.title}</span>
            <small>{item.description}</small>
          </button>
        ))}
      </aside>

      <article className="skill-detail">
        {selected && source ? (
          <>
            <div className="skill-heading">
              <div>
                <p className="eyebrow">{selected.tags.join(" / ")}</p>
                <h2>{selected.title}</h2>
                <p>{selected.description}</p>
              </div>
              <div className="actions">
                <CopyButton text={source.raw}>Copy original</CopyButton>
                <CopyButton text={source.body}>Copy body</CopyButton>
                <CopyButton text={selected.installCommand}>Copy install</CopyButton>
              </div>
            </div>

            <dl className="metadata">
              {Object.entries(source.frontmatter).map(([key, value]) => (
                <div key={key}>
                  <dt>{key}</dt>
                  <dd>{value}</dd>
                </div>
              ))}
            </dl>

            <div className="tabs">
              <button className={!rawMode ? "active" : ""} onClick={() => setRawMode(false)}>
                Preview
              </button>
              <button className={rawMode ? "active" : ""} onClick={() => setRawMode(true)}>
                Raw
              </button>
            </div>

            {rawMode ? <pre className="raw">{source.raw}</pre> : <MarkdownPreview body={source.body} />}
          </>
        ) : (
          <p className="empty">Skill 없음.</p>
        )}
      </article>
    </section>
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
    <button onClick={copy} title={state === "failed" ? "복사 실패. Raw 탭에서 수동 복사." : children}>
      {state === "copied" ? "Copied" : state === "failed" ? "Failed" : children}
    </button>
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
    <div className="markdown">
      {blocks.map((block, index) => {
        if (block.startsWith("```")) {
          return <pre key={index}>{block.replace(/^```\w*\n?|\n?```$/g, "")}</pre>;
        }
        if (block.startsWith("# ")) return <h1 key={index}>{block.slice(2)}</h1>;
        if (block.startsWith("## ")) return <h2 key={index}>{block.slice(3)}</h2>;
        if (block.startsWith("### ")) return <h3 key={index}>{block.slice(4)}</h3>;
        if (block.startsWith("- ")) {
          return (
            <ul key={index}>
              {block.split("\n").map((line) => (
                <li key={line}>{line.replace(/^- /, "")}</li>
              ))}
            </ul>
          );
        }
        return <p key={index}>{block}</p>;
      })}
    </div>
  );
}
