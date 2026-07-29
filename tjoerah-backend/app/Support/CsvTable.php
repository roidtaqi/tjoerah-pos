<?php

namespace App\Support;

use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\StreamedResponse;

class CsvTable
{
    /**
     * @return array<int, array<string, string>>
     */
    public static function read(UploadedFile $file): array
    {
        $path = $file->getRealPath();
        $handle = $path ? fopen($path, 'rb') : false;
        if (! $handle) {
            throw ValidationException::withMessages([
                'file' => 'File CSV tidak dapat dibaca.',
            ]);
        }

        try {
            $firstLine = fgets($handle);
            if ($firstLine === false) {
                throw ValidationException::withMessages([
                    'file' => 'File CSV kosong.',
                ]);
            }
            $delimiter = substr_count($firstLine, ';') > substr_count($firstLine, ',')
                ? ';'
                : ',';
            rewind($handle);

            $headers = fgetcsv($handle, separator: $delimiter);
            if (! is_array($headers)) {
                throw ValidationException::withMessages([
                    'file' => 'Header CSV tidak ditemukan.',
                ]);
            }
            $headers = array_map(self::normalizeHeader(...), $headers);
            if (count(array_unique($headers)) !== count($headers)) {
                throw ValidationException::withMessages([
                    'file' => 'Header CSV memiliki nama kolom yang sama.',
                ]);
            }

            $rows = [];
            $lineNumber = 1;
            while (($values = fgetcsv($handle, separator: $delimiter)) !== false) {
                $lineNumber++;
                $values = array_map(
                    fn ($value) => trim((string) $value),
                    array_pad($values, count($headers), ''),
                );
                if (collect($values)->every(fn ($value) => $value === '')) {
                    continue;
                }
                $row = array_combine($headers, array_slice($values, 0, count($headers)));
                $rows[] = [
                    ...$row,
                    '_line' => (string) $lineNumber,
                ];
            }

            if ($rows === []) {
                throw ValidationException::withMessages([
                    'file' => 'CSV belum memiliki baris data.',
                ]);
            }

            return $rows;
        } finally {
            fclose($handle);
        }
    }

    /**
     * @param  array<int, string>  $headers
     * @param  array<int, array<int, mixed>>  $rows
     */
    public static function download(
        string $filename,
        array $headers,
        array $rows,
    ): StreamedResponse {
        return response()->streamDownload(function () use ($headers, $rows): void {
            $output = fopen('php://output', 'wb');
            fwrite($output, "\xEF\xBB\xBF");
            fputcsv($output, $headers);
            foreach ($rows as $row) {
                fputcsv($output, $row);
            }
            fclose($output);
        }, $filename, [
            'Content-Type' => 'text/csv; charset=UTF-8',
        ]);
    }

    /**
     * @param  array<int, array<string, string>>  $rows
     * @param  array<int, string>  $required
     */
    public static function requireHeaders(array $rows, array $required): void
    {
        $headers = array_keys($rows[0] ?? []);
        $missing = array_values(array_diff($required, $headers));
        if ($missing !== []) {
            throw ValidationException::withMessages([
                'file' => 'Kolom wajib belum ada: '.implode(', ', $missing).'.',
            ]);
        }
    }

    private static function normalizeHeader(mixed $header): string
    {
        return strtolower(trim(
            str_replace("\xEF\xBB\xBF", '', (string) $header),
        ));
    }
}
