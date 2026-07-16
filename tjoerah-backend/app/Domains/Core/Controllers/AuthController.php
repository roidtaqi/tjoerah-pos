<?php

namespace App\Domains\Core\Controllers;

use App\Domains\Core\Models\User;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AuthController extends Controller
{
    public function login(Request $request)
    {
        $request->validate([
            'email' => 'required_without:pin|email',
            'password' => 'required_without:pin',
            'pin' => 'required_without:email',
        ]);

        if ($request->has('pin') && $request->pin) {
            $user = User::where('pin', $request->pin)->first();
            if (! $user) {
                return response()->json([
                    'message' => 'Invalid PIN.',
                    'errors' => ['pin' => ['Invalid PIN.']],
                ], 401);
            }
            $token = Auth::guard('api')->login($user);
        } else {
            $credentials = $request->only('email', 'password');
            if (! $token = Auth::guard('api')->attempt($credentials)) {
                return response()->json([
                    'message' => 'Invalid credentials.',
                    'errors' => ['email' => ['Invalid credentials.']],
                ], 401);
            }
            $user = Auth::guard('api')->user();
        }

        $user->forceFill(['last_login_at' => now()])->save();

        return $this->respondWithToken($token);
    }

    public function me()
    {
        return response()->json([
            'user' => Auth::guard('api')->user()->load('outlets'),
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
            'user' => Auth::guard('api')->user()->load('outlets'),
            'token' => $token,
            'token_type' => 'bearer',
            'expires_in' => Auth::guard('api')->factory()->getTTL() * 60,
        ]);
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
        $request->merge(['pin' => $request->input('pin')]);

        return $this->login($request);
    }
}
