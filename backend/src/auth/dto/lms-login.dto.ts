import { Transform } from 'class-transformer';
import type { TransformFnParams } from 'class-transformer';
import { IsIn, IsString, MaxLength, MinLength } from 'class-validator';
import type { LmsUserRole } from '../../lms/contracts/lms-types';

export class LmsLoginDto {
  @IsIn(['student', 'teacher', 'admin'])
  role!: LmsUserRole;

  @Transform(({ value }: TransformFnParams) => {
    const input: unknown = value;
    return typeof input === 'string' ? input.trim() : input;
  })
  @IsString()
  @MinLength(1)
  @MaxLength(320)
  username!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  password!: string;
}
