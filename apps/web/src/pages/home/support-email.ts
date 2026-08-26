/**
 * The `mailto:` URI for one support message.
 *
 * Built by hand rather than with `URLSearchParams`, which encodes spaces as
 * `+`: correct for form bodies, wrong in a mail subject, where several clients
 * show the plus signs verbatim.
 */
export function supportMailtoHref({
    address,
    subject,
    body,
}: {
    address: string
    subject: string
    body: string
}): string {
    return (
        `mailto:${address}` +
        `?subject=${encodeURIComponent(subject)}` +
        `&body=${encodeURIComponent(body)}`
    )
}
