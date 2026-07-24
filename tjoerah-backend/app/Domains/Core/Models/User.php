<?php

namespace App\Domains\Core\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use App\Domains\Core\Models\Concerns\HasUuid;
use App\Domains\Employee\Models\Employee;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use PHPOpenSourceSaver\JWTAuth\Contracts\JWTSubject;

#[Hidden(['password', 'pin', 'remember_token'])]
class User extends Authenticatable implements JWTSubject
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, HasUuid, Notifiable, SoftDeletes;

    protected $guarded = [];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }

    public function outlets(): BelongsToMany
    {
        return $this->belongsToMany(Outlet::class);
    }

    public function roles(): BelongsToMany
    {
        return $this->belongsToMany(Role::class, 'user_roles')
            ->withPivot(['company_id', 'brand_id', 'outlet_id'])
            ->withTimestamps();
    }

    public function employee()
    {
        return $this->hasOne(Employee::class);
    }

    /**
     * Get the identifier that will be stored in the subject claim of the JWT.
     *
     * @return mixed
     */
    public function getJWTIdentifier()
    {
        return $this->getKey();
    }

    /**
     * Return a key value array, containing any custom claims to be added to the JWT.
     *
     * @return array
     */
    public function getJWTCustomClaims()
    {
        return [
            'uuid' => $this->uuid,
            'company_id' => $this->company_id,
        ];
    }
}
