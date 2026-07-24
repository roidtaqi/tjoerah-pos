<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureUserHasRole
{
    /**
     * @param  Closure(Request): Response  $next
     */
    public function handle(Request $request, Closure $next, string ...$allowedRoles): Response
    {
        $user = $request->user('api') ?? $request->user();

        if (! $user) {
            return response()->json(['message' => 'Unauthenticated.'], 401);
        }

        $roles = collect([$user->role])
            ->merge($user->roles()->get(['slug', 'name'])->flatMap(
                fn ($role) => [$role->slug, $role->name],
            ))
            ->filter()
            ->map(fn ($role) => $this->normalizeRole((string) $role));

        $allowed = collect($allowedRoles)
            ->map(fn ($role) => $this->normalizeRole($role));

        if ($roles->intersect($allowed)->isEmpty()) {
            return response()->json([
                'message' => 'Anda tidak memiliki izin untuk melakukan tindakan ini.',
            ], 403);
        }

        return $next($request);
    }

    private function normalizeRole(string $role): string
    {
        $normalized = str_replace(['-', ' '], '_', strtolower(trim($role)));
        if (str_contains($normalized, 'admin')) {
            return 'admin';
        }
        if (str_contains($normalized, 'owner')) {
            return 'owner';
        }

        return $normalized;
    }
}
