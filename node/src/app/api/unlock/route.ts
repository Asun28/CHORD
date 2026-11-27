// POST /api/unlock; every other method answers 404 with a contacts parameter, else 405.
export { unlock as POST, otherMethod as GET, otherMethod as HEAD, otherMethod as PUT, otherMethod as PATCH, otherMethod as DELETE, otherMethod as OPTIONS } from "@/server/session.ts";
