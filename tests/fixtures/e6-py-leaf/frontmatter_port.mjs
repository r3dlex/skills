import { frontmatterName } from "../../../scripts/lib/leaf/frontmatter.mjs";

process.stdout.write(`${frontmatterName(process.argv[2])}\n`);
