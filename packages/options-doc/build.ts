interface NixosOption {
  declarations: Array<{ url: string | null; source: string }>;
  default?: { _type?: string; text?: string } | unknown;
  description?: string;
  example?: { _type?: string; text?: string } | unknown;
  readOnly?: boolean;
  type?: string;
}

interface OptionDoc {
  id: string;
  name: string;
  namespace: string;
  type: string;
  description: string;
  descriptionPlain: string;
  default: string;
  example: string;
  declarations: Array<{ url: string | null; source: string }>;
  readOnly: boolean;
}

interface TocNode {
  name: string;
  fullPath: string;
  children: Record<string, TocNode>;
  hasOptions: boolean;
}

function parseArgs(args: string[]): { options: string; output: string } {
  let options = "";
  let output = "";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--options" && args[i + 1]) {
      options = args[++i];
    } else if (args[i] === "--output" && args[i + 1]) {
      output = args[++i];
    }
  }

  return { options, output };
}

function formatValue(value: unknown): string {
  if (value === null || value === undefined) {
    return "";
  }
  if (typeof value === "object" && value !== null) {
    const obj = value as { _type?: string; text?: string };
    if (obj._type === "literalExpression" || obj._type === "literalMD") {
      return obj.text ?? "";
    }
  }
  if (typeof value === "string") {
    return value;
  }
  return JSON.stringify(value, null, 2);
}

function stripMarkdown(text: string): string {
  return text
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/^#+\s*/gm, "")
    .replace(/<[^>]+>/g, "");
}

function getNamespace(name: string): string {
  const parts = name.split(".");
  if (parts.length <= 1) return "root";
  return parts[0];
}

function buildToc(optionNames: string[]): TocNode {
  const root: TocNode = {
    name: "",
    fullPath: "",
    children: {},
    hasOptions: false,
  };

  for (const name of optionNames) {
    const parts = name.split(".");
    let current = root;
    let path = "";

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      path = path ? `${path}.${part}` : part;

      if (!current.children[part]) {
        current.children[part] = {
          name: part,
          fullPath: path,
          children: {},
          hasOptions: false,
        };
      }
      current = current.children[part];

      if (i === parts.length - 1) {
        current.hasOptions = true;
      }
    }
  }

  return root;
}

function tocToJson(node: TocNode, maxDepth: number = 10, depth: number = 0): unknown {
  const children = Object.entries(node.children)
    .sort(([a], [b]) => a.localeCompare(b))
    .filter(([, child]) => depth < maxDepth || Object.keys(child.children).length > 0)
    .map(([, child]) => tocToJson(child, maxDepth, depth + 1));

  return {
    name: node.name,
    fullPath: node.fullPath,
    hasOptions: node.hasOptions,
    children: children.length > 0 ? children : undefined,
  };
}

async function main() {
  const args = parseArgs(Deno.args);

  if (!args.options || !args.output) {
    console.error("Usage: build.ts --options <path> --output <path>");
    Deno.exit(1);
  }

  console.log(`Reading options from ${args.options}`);
  const optionsJson = await Deno.readTextFile(args.options);
  const options: Record<string, NixosOption> = JSON.parse(optionsJson);

  console.log(`Found ${Object.keys(options).length} options`);

  // Transform options for client-side use
  const docs: OptionDoc[] = Object.entries(options).map(([name, opt]) => ({
    id: name,
    name,
    namespace: getNamespace(name),
    type: opt.type ?? "unknown",
    description: opt.description ?? "",
    descriptionPlain: stripMarkdown(opt.description ?? ""),
    default: formatValue(opt.default),
    example: formatValue(opt.example),
    declarations: opt.declarations ?? [],
    readOnly: opt.readOnly ?? false,
  }));

  console.log("Building TOC...");
  const toc = buildToc(Object.keys(options));
  const tocJson = tocToJson(toc);

  console.log(`Creating output directory ${args.output}`);
  await Deno.mkdir(args.output, { recursive: true });

  // Write options data for client-side Orama indexing
  await Deno.writeTextFile(`${args.output}/options-data.json`, JSON.stringify(docs));
  console.log("Wrote options-data.json");

  await Deno.writeTextFile(`${args.output}/toc.json`, JSON.stringify(tocJson, null, 2));
  console.log("Wrote toc.json");

  const srcDir = new URL(".", import.meta.url).pathname;

  const template = await Deno.readTextFile(`${srcDir}/templates/index.html`);
  await Deno.writeTextFile(`${args.output}/index.html`, template);
  console.log("Wrote index.html");

  await Deno.copyFile(`${srcDir}/static/style.css`, `${args.output}/style.css`);
  console.log("Wrote style.css");

  await Deno.copyFile(`${srcDir}/static/app.js`, `${args.output}/app.js`);
  console.log("Wrote app.js");

  console.log("Build complete!");
}

main();
