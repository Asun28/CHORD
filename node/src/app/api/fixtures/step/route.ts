export async function POST(): Promise<Response> {
  return Response.json({ cursor: 0 });
}
