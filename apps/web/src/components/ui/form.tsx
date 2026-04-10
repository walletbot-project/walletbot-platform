import type { AnyFieldApi } from "@tanstack/react-form"

import { cn } from "@/lib/utils"
import { Label } from "@/components/ui/label"

/**
 * Extracts the first error message from a TanStack Form field.
 */
function getFieldError(field: AnyFieldApi): string | undefined {
  if (!field.state.meta.isTouched) return undefined
  const errors = field.state.meta.errors
  if (!errors.length) return undefined
  const first = errors[0]
  if (typeof first === "string") return first
  if (first && typeof first === "object" && "message" in first) {
    return (first as { message: string }).message
  }
  return String(first)
}

// ─── FormField ───────────────────────────────────────────────────────────────

interface FormFieldProps {
  field: AnyFieldApi
  label?: string
  description?: string
  children: React.ReactNode
  className?: string
}

/**
 * Wraps any input with a consistent label, description, and error message.
 *
 * Usage:
 * ```tsx
 * <form.Field
 *   name="email"
 *   children={(field) => (
 *     <FormField field={field} label="Email" description="Your work email">
 *       <Input
 *         value={field.state.value}
 *         onChange={(e) => field.handleChange(e.target.value)}
 *         onBlur={field.handleBlur}
 *       />
 *     </FormField>
 *   )}
 * />
 * ```
 */
function FormField({
  field,
  label,
  description,
  children,
  className,
}: FormFieldProps) {
  const error = getFieldError(field)
  const fieldId = field.name

  return (
    <div
      data-slot="form-field"
      className={cn("flex flex-col gap-1.5", className)}
    >
      {label && <Label htmlFor={fieldId}>{label}</Label>}
      {description && (
        <p className="text-xs text-muted-foreground">{description}</p>
      )}
      <div
        aria-invalid={!!error}
        data-invalid={!!error || undefined}
      >
        {children}
      </div>
      {error && (
        <p
          data-slot="form-error"
          className="text-xs text-destructive"
          role="alert"
        >
          {error}
        </p>
      )}
    </div>
  )
}

// ─── FormActions ─────────────────────────────────────────────────────────────

interface FormActionsProps {
  children: React.ReactNode
  className?: string
}

/**
 * Standardized form action row. Use with `form.Subscribe` for submit state.
 *
 * Usage:
 * ```tsx
 * <form.Subscribe
 *   selector={(state) => [state.canSubmit, state.isSubmitting]}
 *   children={([canSubmit, isSubmitting]) => (
 *     <FormActions>
 *       <Button variant="outline" onClick={onCancel} disabled={isSubmitting}>
 *         Cancel
 *       </Button>
 *       <Button type="submit" disabled={!canSubmit}>
 *         {isSubmitting ? "Saving..." : "Save"}
 *       </Button>
 *     </FormActions>
 *   )}
 * />
 * ```
 */
function FormActions({ children, className }: FormActionsProps) {
  return (
    <div
      data-slot="form-actions"
      className={cn("flex items-center justify-end gap-2", className)}
    >
      {children}
    </div>
  )
}

// ─── FormSection ─────────────────────────────────────────────────────────────

interface FormSectionProps {
  title?: string
  description?: string
  children: React.ReactNode
  className?: string
}

/**
 * Groups related fields with a heading. For multi-section forms.
 */
function FormSection({
  title,
  description,
  children,
  className,
}: FormSectionProps) {
  return (
    <fieldset
      data-slot="form-section"
      className={cn("flex flex-col gap-4", className)}
    >
      {(title || description) && (
        <div className="flex flex-col gap-1">
          {title && (
            <legend className="text-sm font-medium">{title}</legend>
          )}
          {description && (
            <p className="text-xs text-muted-foreground">{description}</p>
          )}
        </div>
      )}
      {children}
    </fieldset>
  )
}

export { FormActions, FormField, FormSection, getFieldError }
