<?php

namespace App\Domains\Core\Controllers;

use App\Domains\Core\Models\Outlet;
use App\Domains\Core\Models\User;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    public function login(Request $request)
    {
        $validated = $request->validate([
            'identifier' => 'required_without:email|string|max:255',
            'email' => 'required_without:identifier|email|max:255',
            'password' => 'required|string|max:255',
        ]);

        $user = $this->findActiveUser(
            $validated['identifier'] ?? $validated['email'],
        );
        if (! $user || ! Hash::check($validated['password'], $user->password)) {
            return $this->invalidCredentials();
        }

        return $this->authenticate($user);
    }

    public function me()
    {
        return response()->json([
            'user' => $this->authenticatedUser(),
        ]);
    }

    public function logout()
    {
        Auth::guard('api')->logout();

        return response()->json(['message' => 'Logged out.']);
    }

    public function refresh()
    {
        return $this->respondWithToken(Auth::guard('api')->refresh());
    }

    protected function respondWithToken($token)
    {
        return response()->json([
            'user' => $this->authenticatedUser(),
            'token' => $token,
            'token_type' => 'bearer',
            'expires_in' => Auth::guard('api')->factory()->getTTL() * 60,
        ]);
    }

    private function authenticatedUser(): User
    {
        $user = Auth::guard('api')->user()->load('roles');
        $outlets = $user->company_id
            ? Outlet::query()
                ->where('company_id', $user->company_id)
                ->where('is_active', true)
                ->orderBy('name')
                ->get()
            : $user->outlets()
                ->where('is_active', true)
                ->orderBy('name')
                ->get();

        return $user->setRelation('outlets', $outlets);
    }

    public function registerDevice(Request $request)
    {
        $validated = $request->validate([
            'device_id' => 'required|string|max:255',
            'device_name' => 'nullable|string|max:255',
            'platform' => 'nullable|string|max:100',
            'outlet_id' => 'nullable|integer|exists:outlets,id',
        ]);

        return response()->json([
            'message' => 'Device registered.',
            'device' => $validated,
            'biometric_ready' => true,
        ], 201);
    }

    public function pinLogin(Request $request)
    {
        $validated = $request->validate([
            'identifier' => 'required|string|max:255',
            'pin' => 'required|digits_between:4,6',
        ]);
        $user = $this->findActiveUser($validated['identifier']);
        if (! $user || ! hash_equals((string) $user->pin, (string) $validated['pin'])) {
            return $this->invalidCredentials();
        }

        return $this->authenticate($user);
    }

    private function authenticate(User $user)
    {
        $token = Auth::guard('api')->login($user);
        $user->forceFill(['last_login_at' => now()])->save();

        return $this->respondWithToken($token);
    }

    private function findActiveUser(string $identifier): ?User
    {
        $normalizedIdentifier = Str::lower(trim($identifier));
        $normalizedPhone = $this->normalizePhone($identifier);

        $matches = User::query()
            ->where('is_active', true)
            ->where(function ($query) use ($normalizedIdentifier, $normalizedPhone): void {
                $query->whereRaw('LOWER(email) = ?', [$normalizedIdentifier])
                    ->orWhereRaw('LOWER(username) = ?', [$normalizedIdentifier]);
                if ($normalizedPhone !== null) {
                    $query->orWhere('phone', $normalizedPhone);
                }
            })
            ->limit(2)
            ->get();

        return $matches->count() === 1 ? $matches->first() : null;
    }

    private function normalizePhone(string $value): ?string
    {
        $phone = preg_replace('/\D+/', '', $value) ?? '';
        if (strlen($phone) < 8) {
            return null;
        }
        if (str_starts_with($phone, '0')) {
            $phone = '62'.substr($phone, 1);
        }

        return $phone;
    }

    private function invalidCredentials()
    {
        return response()->json([
            'message' => 'Invalid credentials.',
            'errors' => ['identifier' => ['Invalid credentials.']],
        ], 401);
    }
}
