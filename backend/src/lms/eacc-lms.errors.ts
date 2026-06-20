export class InvalidLmsCredentialsError extends Error {
  constructor() {
    super('The LMS rejected the supplied credentials.');
  }
}

export class LmsUnavailableError extends Error {
  constructor() {
    super('The LMS is currently unavailable.');
  }
}

export class InvalidLmsResponseError extends Error {
  constructor(message = 'The LMS returned an unsupported response.') {
    super(message);
  }
}
