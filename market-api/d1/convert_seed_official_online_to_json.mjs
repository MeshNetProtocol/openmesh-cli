import fs from "node:fs";
import path from "node:path";

function findValuesSQL(sql) {
  const marker = ") VALUES (";
  const start = sql.indexOf(marker);
  if (start < 0) throw new Error("VALUES block not found");
  const from = start + marker.length;
  const end = sql.indexOf(");", from);
  if (end < 0) throw new Error("VALUES block end not found");
  return sql.slice(from, end);
}

function parseValues(valuesSQL) {
  const values = [];
  let i = 0;
  let current = "";
  let inString = false;

  while (i < valuesSQL.length) {
    const ch = valuesSQL[i];
    if (inString) {
      if (ch === "'") {
        const next = valuesSQL[i + 1];
        if (next === "'") {
          current += "'";
          i += 2;
          continue;
        }
        inString = false;
        current += "'";
        i += 1;
        continue;
      }
      current += ch;
      i += 1;
      continue;
    }

    if (ch === "'") {
      inString = true;
      current += "'";
      i += 1;
      continue;
    }

    if (ch === ",") {
      const trimmed = current.trim();
      if (trimmed.length) values.push(trimmed);
      current = "";
      i += 1;
      continue;
    }

    current += ch;
    i += 1;
  }

  const trimmed = current.trim();
  if (trimmed.length) values.push(trimmed);
  return values;
}

function evalSQLStringExpression(expr) {
  const parts = expr.split("||").map((p) => p.trim()).filter(Boolean);
  if (parts.length === 0) return "";
  let out = "";
  for (const p of parts) {
    if (!p.startsWith("'") || !p.endsWith("'")) {
      throw new Error(`unsupported expression part: ${p.slice(0, 80)}`);
    }
    const inner = p.slice(1, -1).replaceAll("''", "'");
    out += inner;
  }
  return out;
}

function stripSQLString(expr) {
  const t = expr.trim();
  if (!t.startsWith("'") || !t.endsWith("'")) return null;
  return t.slice(1, -1).replaceAll("''", "'");
}

function buildSeedJSON(sql) {
  const valuesSQL = findValuesSQL(sql);
  const items = parseValues(valuesSQL);
  if (items.length !== 11) {
    throw new Error(`unexpected values count=${items.length}`);
  }

  const [
    idExpr,
    nameExpr,
    descriptionExpr,
    tagsExpr,
    authorExpr,
    updatedAtExpr,
    priceExpr,
    visibilityExpr,
    statusExpr,
    configExpr,
    routingRulesExpr,
  ] = items;

  const provider_id = stripSQLString(idExpr) ?? "";
  const name = stripSQLString(nameExpr) ?? "";
  const description = stripSQLString(descriptionExpr) ?? "";
  const tags_json = stripSQLString(tagsExpr) ?? "[]";
  const author = stripSQLString(authorExpr) ?? "";
  const source_updated_at = stripSQLString(updatedAtExpr) ?? "";
  const visibility = stripSQLString(visibilityExpr) ?? "";
  const status = stripSQLString(statusExpr) ?? "";

  const configJSON = evalSQLStringExpression(configExpr);
  const routingRulesJSON = evalSQLStringExpression(routingRulesExpr);

  const config = JSON.parse(configJSON);
  const routing_rules = JSON.parse(routingRulesJSON);
  const tags = JSON.parse(tags_json);

  return {
    provider_id,
    name,
    description,
    tags,
    author,
    visibility,
    status,
    updated_at: "1970-01-01T00:00:00Z",
    package_hash: "seed-0",
    source_updated_at,
    config,
    routing_rules,
  };
}

const repoRoot = path.resolve(process.cwd(), "..");
const inPath = path.join(repoRoot, "market-api", "d1", "002_seed_official_online.sql");
const outPath = path.join(repoRoot, "market-api", "d1", "002_seed_official_online.json");

const sql = fs.readFileSync(inPath, "utf8");
const json = buildSeedJSON(sql);
fs.writeFileSync(outPath, JSON.stringify(json, null, 2) + "\n");
process.stdout.write(outPath + "\n");
