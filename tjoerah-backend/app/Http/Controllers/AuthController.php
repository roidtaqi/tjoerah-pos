<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

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
                throw ValidationException::withMessages(['pin' => 'Invalid PIN.']);
            }
        } else {
            $user = User::where('email', $request->email)->first();
            if (! $user || ! Hash::check($request->password, $user->password)) {
                throw ValidationException::withMessages(['email' => 'Invalid credentials.']);
            }
        }

        $token = $user->createToken('pos-token')->plainTextToken;
        $user->forceFill(['last_login_at' => now()])->save();

        return response()->json([
            'user' => $user->load('outlets'),
            'token' => $token,
        ]);
    }

    public function me(Request $request)
    {
        return response()->json([
            'user' => $request->user()->load('outlets')
        ]);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();
        return response()->json(['message' => 'Logged out.']);
    }

    public function refresh(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'token' => $request->user()->createToken('pos-token')->plainTextToken,
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
